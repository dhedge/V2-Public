import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { expect } from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import { checkAlmostSame } from "../../../testHelpers";
import {
  IERC20,
  IVelodromeNonfungiblePositionManager,
  IVelodromeNonfungiblePositionManager__factory,
  PoolFactory,
  PoolLogic,
  PoolManagerLogic,
} from "../../../../types";
import { createFund } from "../../utils/createFund";
import { getAccountToken } from "../../utils/getAccountTokens";
import { utils } from "../../utils/utils";
import { IBackboneDeployments, deployBackboneContracts } from "../../utils/deployContracts/deployBackboneContracts";
import {
  IVelodromeCLTestParams,
  deployVelodromeCLInfrastructure,
  iERC20,
  iERC721,
  iVelodromeCLGauge,
} from "./velodromeCLTestDeploymentHelpers";
import { VelodromeCLMintSettings, getCurrentTick, mintLpAsPool } from "../../utils/velodromeCLUtils";

const deadLine = Math.floor(Date.now() / 1000 + 100000000);

export const velodromeCLAssetGuardTest = (testParams: IVelodromeCLTestParams) => {
  const { pairs, factory } = testParams;
  const { bothSupportedPair } = pairs;

  describe("Velodrome CL Asset Guard Test", function () {
    let deployments: IBackboneDeployments;
    let logicOwner: SignerWithAddress, manager: SignerWithAddress;
    let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
    let tokenId: BigNumber;
    let PROTOCOL_TOKEN: IERC20;
    let nonfungiblePositionManager: IVelodromeNonfungiblePositionManager;
    let token0: IERC20;
    let token1: IERC20;
    const iNonfungiblePositionManager = new ethers.utils.Interface(IVelodromeNonfungiblePositionManager__factory.abi);

    before(async function () {
      deployments = await deployBackboneContracts(testParams);

      manager = deployments.manager;
      logicOwner = deployments.owner;
      poolFactory = deployments.poolFactory;

      ({ nonfungiblePositionManager, PROTOCOL_TOKEN } = await deployVelodromeCLInfrastructure(deployments, testParams));

      const funds = await createFund(
        poolFactory,
        logicOwner,
        manager,
        [
          { asset: bothSupportedPair.token0, isDeposit: true },
          { asset: bothSupportedPair.token1, isDeposit: true },
          { asset: PROTOCOL_TOKEN.address, isDeposit: false },
          { asset: nonfungiblePositionManager.address, isDeposit: false },
        ],
        {
          performance: BigNumber.from("0"),
          management: BigNumber.from("0"),
        },
      );
      poolLogicProxy = funds.poolLogicProxy;
      poolManagerLogicProxy = funds.poolManagerLogicProxy;

      const AMOUNT_MULTIPLIER = 5;

      await getAccountToken(
        bothSupportedPair.amount0.mul(AMOUNT_MULTIPLIER),
        logicOwner.address,
        bothSupportedPair.token0,
        bothSupportedPair.token0Slot,
      );
      await getAccountToken(
        bothSupportedPair.amount1.mul(AMOUNT_MULTIPLIER),
        logicOwner.address,
        bothSupportedPair.token1,
        bothSupportedPair.token1Slot,
      );

      token0 = await ethers.getContractAt("IERC20", bothSupportedPair.token0);
      token1 = await ethers.getContractAt("IERC20", bothSupportedPair.token1);

      await token0.approve(poolLogicProxy.address, bothSupportedPair.amount0.mul(AMOUNT_MULTIPLIER));
      await poolLogicProxy.deposit(bothSupportedPair.token0, bothSupportedPair.amount0.mul(AMOUNT_MULTIPLIER));

      await token1.approve(poolLogicProxy.address, bothSupportedPair.amount1.mul(AMOUNT_MULTIPLIER));
      await poolLogicProxy.deposit(bothSupportedPair.token1, bothSupportedPair.amount1.mul(AMOUNT_MULTIPLIER));
      let approveABI = iERC20.encodeFunctionData("approve", [
        nonfungiblePositionManager.address,
        bothSupportedPair.amount0.mul(2),
      ]);
      await poolLogicProxy.connect(manager).execTransaction(bothSupportedPair.token0, approveABI);
      approveABI = iERC20.encodeFunctionData("approve", [
        nonfungiblePositionManager.address,
        bothSupportedPair.amount1.mul(2),
      ]);
      await poolLogicProxy.connect(manager).execTransaction(bothSupportedPair.token1, approveABI);

      const tickSpacing = bothSupportedPair.tickSpacing;
      const tick = await getCurrentTick(factory, bothSupportedPair);
      const mintSettings: VelodromeCLMintSettings = {
        token0: bothSupportedPair.token0,
        token1: bothSupportedPair.token1,
        tickSpacing,
        amount0: bothSupportedPair.amount0,
        amount1: bothSupportedPair.amount1,
        tickLower: tick - tickSpacing,
        tickUpper: tick + tickSpacing,
      };

      await mintLpAsPool(nonfungiblePositionManager.address, poolLogicProxy, manager, mintSettings);

      tokenId = await nonfungiblePositionManager.tokenOfOwnerByIndex(poolLogicProxy.address, 0);

      const increaseLiquidityABI = iNonfungiblePositionManager.encodeFunctionData("increaseLiquidity", [
        [tokenId, bothSupportedPair.amount0, bothSupportedPair.amount1, 0, 0, deadLine],
      ]);
      await poolLogicProxy.connect(manager).execTransaction(nonfungiblePositionManager.address, increaseLiquidityABI);

      //approve for staking in gauge
      approveABI = iERC721.encodeFunctionData("approve", [bothSupportedPair.gauge, tokenId]);
      await poolLogicProxy.connect(manager).execTransaction(nonfungiblePositionManager.address, approveABI);

      const depositTx = iVelodromeCLGauge.encodeFunctionData("deposit(uint256)", [tokenId]);

      await poolLogicProxy.connect(manager).execTransaction(bothSupportedPair.gauge, depositTx);

      await poolFactory.setExitCooldown(0);
      await ethers.provider.send("evm_increaseTime", [3600 * 24 * 3]); // 3 days
      await ethers.provider.send("evm_mine", []);
    });

    utils.beforeAfterReset(beforeEach, afterEach);

    describe("withdrawProcessing", () => {
      it("Pool has expected funds after withdraw", async () => {
        const token0BalanceBefore = await token0.balanceOf(poolLogicProxy.address);
        const token1BalanceBefore = await token1.balanceOf(poolLogicProxy.address);
        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
        const positionBefore = await nonfungiblePositionManager.positions(tokenId);

        // withdraw half
        await poolLogicProxy.withdraw((await poolLogicProxy.balanceOf(logicOwner.address)).div(2));

        const positionAfter = await nonfungiblePositionManager.positions(tokenId);

        // includes additional rewards, hence 0.005% threshold
        checkAlmostSame(await token0.balanceOf(poolLogicProxy.address), token0BalanceBefore.div(2), 0.001);
        checkAlmostSame(await token1.balanceOf(poolLogicProxy.address), token1BalanceBefore.div(2), 0.001);
        checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore.div(2), 0.005); // includes additional rewards, hence 0.05% threshold
        checkAlmostSame(positionAfter.liquidity, positionBefore.liquidity.div(2), 0.001);
      });

      it("Withdrawer has expected funds after withdraw", async () => {
        const userToken0BalanceBefore = await token0.balanceOf(logicOwner.address);
        const userToken1BalanceBefore = await token1.balanceOf(logicOwner.address);
        const poolTotalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

        // withdraw half
        await poolLogicProxy.withdraw((await poolLogicProxy.balanceOf(logicOwner.address)).div(2));

        const poolTotalFundValueAfter = await poolManagerLogicProxy.totalFundValue();
        const poolRewardsValue = await poolManagerLogicProxy["assetValue(address,uint256)"](
          PROTOCOL_TOKEN.address,
          await PROTOCOL_TOKEN.balanceOf(poolLogicProxy.address),
        );
        const userToken0BalanceAfter = await token0.balanceOf(logicOwner.address);
        const userToken1BalanceAfter = await token1.balanceOf(logicOwner.address);

        const withdrawRewardsValue = await poolManagerLogicProxy["assetValue(address,uint256)"](
          PROTOCOL_TOKEN.address,
          await PROTOCOL_TOKEN.balanceOf(logicOwner.address),
        );
        const withdrawToken0Value = await poolManagerLogicProxy["assetValue(address,uint256)"](
          token0.address,
          userToken0BalanceAfter.sub(userToken0BalanceBefore),
        );
        const withdrawToken1Value = await poolManagerLogicProxy["assetValue(address,uint256)"](
          token1.address,
          userToken1BalanceAfter.sub(userToken1BalanceBefore),
        );
        const withdrawValue = withdrawToken0Value.add(withdrawToken1Value).add(withdrawRewardsValue);
        expect(userToken1BalanceAfter).gt(userToken1BalanceBefore);
        expect(userToken0BalanceAfter).gt(userToken0BalanceBefore);
        checkAlmostSame(poolRewardsValue, withdrawRewardsValue, 0.0001);
        checkAlmostSame(withdrawValue, poolTotalFundValueBefore.sub(poolTotalFundValueAfter), 0.0001); // includes additional rewards, hence 0.005% threshold
        checkAlmostSame(withdrawValue, poolTotalFundValueBefore.div(2), 0.0001);
      });

      it("Pool and Withdrawer receives expected rewards (rewardToken is supported Asset)", async () => {
        const gauge = await ethers.getContractAt("IVelodromeCLGauge", bothSupportedPair.gauge);
        const claimAmount = await gauge.earned(poolLogicProxy.address, tokenId);
        const rewards = await gauge.rewards(tokenId);
        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
        expect(claimAmount).to.gt(0);

        // withdraw half
        await poolLogicProxy.withdraw((await poolLogicProxy.balanceOf(logicOwner.address)).div(2));
        const poolRewardBalance = await PROTOCOL_TOKEN.balanceOf(poolLogicProxy.address);
        const withdrawerRewardBalance = await PROTOCOL_TOKEN.balanceOf(logicOwner.address);
        const totalFundValueAfter = await poolManagerLogicProxy.totalFundValue();
        checkAlmostSame(poolRewardBalance.add(withdrawerRewardBalance), claimAmount.add(rewards), 0.005);
        checkAlmostSame(await PROTOCOL_TOKEN.balanceOf(poolLogicProxy.address), claimAmount.add(rewards).div(2), 0.005);
        checkAlmostSame(await PROTOCOL_TOKEN.balanceOf(logicOwner.address), claimAmount.add(rewards).div(2), 0.005);
        checkAlmostSame(totalFundValueAfter, totalFundValueBefore.div(2), 0.0005);
      });

      it("Pool and Withdrawer receives expected rewards (rewardToken is not supported Asset)", async () => {
        // set rewardToken as not supported Asset
        // to test withdrawal will handle transfer of rewardToken even if it is not a supported Asset
        await poolManagerLogicProxy.changeAssets([], [PROTOCOL_TOKEN.address]);

        const gauge = await ethers.getContractAt("IVelodromeCLGauge", bothSupportedPair.gauge);
        const claimAmount = await gauge.earned(poolLogicProxy.address, tokenId);
        const rewards = await gauge.rewards(tokenId);
        expect(claimAmount).to.gt(0);
        // withdraw half
        await poolLogicProxy.withdraw((await poolLogicProxy.balanceOf(logicOwner.address)).div(2));
        const poolRewardBalance = await PROTOCOL_TOKEN.balanceOf(poolLogicProxy.address);
        const withdrawerRewardBalance = await PROTOCOL_TOKEN.balanceOf(logicOwner.address);

        checkAlmostSame(poolRewardBalance.add(withdrawerRewardBalance), claimAmount.add(rewards), 0.005);
        checkAlmostSame(await PROTOCOL_TOKEN.balanceOf(poolLogicProxy.address), claimAmount.add(rewards).div(2), 0.005);
        checkAlmostSame(await PROTOCOL_TOKEN.balanceOf(logicOwner.address), claimAmount.add(rewards).div(2), 0.005);
      });
    });
  });
};
