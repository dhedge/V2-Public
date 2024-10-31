import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { expect } from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import { checkAlmostSame } from "../../../testHelpers";
import {
  IERC20,
  IRamsesGaugeV2,
  IRamsesNonfungiblePositionManager,
  IRamsesNonfungiblePositionManager__factory,
  PoolFactory,
  PoolLogic,
  PoolManagerLogic,
} from "../../../../types";
import { createFund } from "../../utils/createFund";
import { getAccountToken } from "../../utils/getAccountTokens";
import { utils } from "../../utils/utils";
import { IBackboneDeployments, deployBackboneContracts } from "../../utils/deployContracts/deployBackboneContracts";

import { mintLpAsPool, RamsesCLMintSettings } from "../../utils/ramsesCLUtils";
import { getCurrentTick } from "../../utils/uniV3Utils";
import { IRamsesCLTestParams, deployRamsesCLInfrastructure, iERC20 } from "./deploymentTestHelpers";

const deadLine = Math.floor(Date.now() / 1000 + 100000000);

export const ramsesCLAssetGuardTest = (testParams: IRamsesCLTestParams) => {
  const { pairs, factory } = testParams;
  const { bothSupportedPair } = pairs;

  describe("Ramses CL Asset Guard Test", function () {
    let deployments: IBackboneDeployments;
    let logicOwner: SignerWithAddress, manager: SignerWithAddress;
    let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
    let tokenId: BigNumber;
    let PROTOCOL_TOKEN: IERC20;
    let nonfungiblePositionManager: IRamsesNonfungiblePositionManager;
    let token0: IERC20;
    let token1: IERC20;
    let gauge: IRamsesGaugeV2;
    const iNonfungiblePositionManager = new ethers.utils.Interface(IRamsesNonfungiblePositionManager__factory.abi);

    before(async function () {
      deployments = await deployBackboneContracts(testParams);

      manager = deployments.manager;
      logicOwner = deployments.owner;
      poolFactory = deployments.poolFactory;

      ({ nonfungiblePositionManager, PROTOCOL_TOKEN, gauge } = await deployRamsesCLInfrastructure(
        deployments,
        testParams,
      ));

      const funds = await createFund(
        poolFactory,
        logicOwner,
        manager,
        [
          { asset: bothSupportedPair.token0, isDeposit: true },
          { asset: bothSupportedPair.token1, isDeposit: true },
          { asset: nonfungiblePositionManager.address, isDeposit: false },
          ...testParams.rewardTokenSettings.map(({ rewardToken }) => ({ asset: rewardToken, isDeposit: false })), // enable reward assets
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
        bothSupportedPair.amount0.mul(AMOUNT_MULTIPLIER),
      ]);
      await poolLogicProxy.connect(manager).execTransaction(bothSupportedPair.token0, approveABI);
      approveABI = iERC20.encodeFunctionData("approve", [
        nonfungiblePositionManager.address,
        bothSupportedPair.amount1.mul(AMOUNT_MULTIPLIER),
      ]);
      await poolLogicProxy.connect(manager).execTransaction(bothSupportedPair.token1, approveABI);

      const fee = bothSupportedPair.fee;
      const tickSpacing = bothSupportedPair.tickSpacing;
      const tick = await getCurrentTick(factory, bothSupportedPair);
      const mintSettings: RamsesCLMintSettings = {
        token0: bothSupportedPair.token0,
        token1: bothSupportedPair.token1,
        fee,
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
        checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore.div(2), 0.05); // includes additional rewards, hence 0.05% threshold
        checkAlmostSame(positionAfter.liquidity, positionBefore.liquidity.div(2), 0.001);
      });

      it("Withdrawer has expected funds after withdraw", async () => {
        const userToken0BalanceBefore = await token0.balanceOf(logicOwner.address);
        const userToken1BalanceBefore = await token1.balanceOf(logicOwner.address);
        const poolTotalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

        // withdraw half
        await poolLogicProxy.withdraw((await poolLogicProxy.balanceOf(logicOwner.address)).div(2));

        const poolTotalFundValueAfter = await poolManagerLogicProxy.totalFundValue();

        // RAM balances
        const poolProtocolTokenBal = await PROTOCOL_TOKEN.balanceOf(poolLogicProxy.address);
        const withdrawProtocolTokenBal = await PROTOCOL_TOKEN.balanceOf(logicOwner.address);

        const userToken0BalanceAfter = await token0.balanceOf(logicOwner.address);
        const userToken1BalanceAfter = await token1.balanceOf(logicOwner.address);

        // withdrawn token0 principal value
        const withdrawToken0Value = await poolManagerLogicProxy["assetValue(address,uint256)"](
          token0.address,
          userToken0BalanceAfter.sub(userToken0BalanceBefore),
        );
        // withdrawn token1 principal value
        const withdrawToken1Value = await poolManagerLogicProxy["assetValue(address,uint256)"](
          token1.address,
          userToken1BalanceAfter.sub(userToken1BalanceBefore),
        );

        // withdrawn rewards value
        const withdrawRewardValue = BigNumber.from(0);
        testParams.rewardTokenSettings.forEach(async ({ rewardToken }) => {
          const rewardTokenContract = await ethers.getContractAt("IERC20", rewardToken);
          const userRewardTokenBalance = await rewardTokenContract.balanceOf(logicOwner.address);
          const withdrawRewardTokenValue = await poolManagerLogicProxy["assetValue(address,uint256)"](
            rewardToken,
            userRewardTokenBalance,
          );
          withdrawRewardValue.add(withdrawRewardTokenValue);
        });

        const withdrawValue = withdrawToken0Value.add(withdrawToken1Value).add(withdrawRewardValue);
        expect(userToken1BalanceAfter).gt(userToken1BalanceBefore);
        expect(userToken0BalanceAfter).gt(userToken0BalanceBefore);
        checkAlmostSame(poolProtocolTokenBal, withdrawProtocolTokenBal, 0.0001);
        checkAlmostSame(withdrawValue, poolTotalFundValueBefore.sub(poolTotalFundValueAfter), 0.05); // includes additional rewards, hence 0.005% threshold
        checkAlmostSame(withdrawValue, poolTotalFundValueBefore.div(2), 0.05);
      });

      it("Pool and Withdrawer receives expected rewards", async () => {
        const earnedProcotolTokenAmount = await gauge.earned(PROTOCOL_TOKEN.address, tokenId);
        // get earned reward tokens amounts
        const rewardTokensInfo = await Promise.all(
          testParams.rewardTokenSettings.map(async ({ rewardToken }) => {
            const tokenContract = await ethers.getContractAt("ERC20", rewardToken);
            const symbol = await tokenContract.symbol();
            const earnedRewardAmount = await gauge.earned(rewardToken, tokenId);
            console.log(`earnedRewardAmount ${symbol}: ${earnedRewardAmount.toString()}`);
            return { earned: earnedRewardAmount, symbol, address: rewardToken };
          }),
        );
        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

        // withdraw half
        await poolLogicProxy.withdraw((await poolLogicProxy.balanceOf(logicOwner.address)).div(2));
        const totalFundValueAfter = await poolManagerLogicProxy.totalFundValue();

        console.log(`earnedProcotolTokenAmount: ${earnedProcotolTokenAmount.toString()}`);
        expect(earnedProcotolTokenAmount).to.gt(0);
        const poolProtocolTokenBalance = await PROTOCOL_TOKEN.balanceOf(poolLogicProxy.address);
        const withdrawerProtocolTokenBalance = await PROTOCOL_TOKEN.balanceOf(logicOwner.address);
        checkAlmostSame(poolProtocolTokenBalance, earnedProcotolTokenAmount.div(2), 0.005);
        checkAlmostSame(withdrawerProtocolTokenBalance, earnedProcotolTokenAmount.div(2), 0.005);

        // check, for each reward token, pool and withdrawer has half of the earned reward
        rewardTokensInfo.forEach(async (rewardTokenInfo) => {
          const tokenContract = await ethers.getContractAt("ERC20", rewardTokenInfo.address);
          const poolRewardTokenBalance = await tokenContract.balanceOf(poolLogicProxy.address);
          const withdrawerRewardTokenBalance = await tokenContract.balanceOf(logicOwner.address);

          checkAlmostSame(poolRewardTokenBalance, rewardTokenInfo.earned.div(2), 0.005);
          checkAlmostSame(withdrawerRewardTokenBalance, rewardTokenInfo.earned.div(2), 0.005);
        });
        checkAlmostSame(totalFundValueAfter, totalFundValueBefore.div(2), 0.05);
      });
    });
  });
};
