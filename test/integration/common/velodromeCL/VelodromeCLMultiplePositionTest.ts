import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import { checkAlmostSame, units } from "../../../testHelpers";
import {
  IERC20,
  IMulticall__factory,
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

export const velodromeCLMultiplePositionTest = (testParams: IVelodromeCLTestParams) => {
  const { pairs, factory } = testParams;
  const { bothSupportedPair } = pairs;

  describe("Velodrome CL Multiple Position Test", function () {
    let deployments: IBackboneDeployments;
    let logicOwner: SignerWithAddress, manager: SignerWithAddress;
    let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
    let tokenId: BigNumber;
    let PROTOCOL_TOKEN: IERC20;
    let nonfungiblePositionManager: IVelodromeNonfungiblePositionManager;
    let token0: IERC20;
    let token1: IERC20;
    const tokenIds: BigNumber[] = [];
    const iNonfungiblePositionManager = new ethers.utils.Interface(IVelodromeNonfungiblePositionManager__factory.abi);
    const iMulticall = new ethers.utils.Interface(IMulticall__factory.abi);

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
        bothSupportedPair.amount0.mul(AMOUNT_MULTIPLIER),
      ]);
      await poolLogicProxy.connect(manager).execTransaction(bothSupportedPair.token0, approveABI);
      approveABI = iERC20.encodeFunctionData("approve", [
        nonfungiblePositionManager.address,
        bothSupportedPair.amount1.mul(AMOUNT_MULTIPLIER),
      ]);
      await poolLogicProxy.connect(manager).execTransaction(bothSupportedPair.token1, approveABI);

      for (const i of [0, 1, 2]) {
        const tickSpacing = bothSupportedPair.tickSpacing;
        const tick = await getCurrentTick(factory, bothSupportedPair);
        const mintSettings: VelodromeCLMintSettings = {
          token0: bothSupportedPair.token0,
          token1: bothSupportedPair.token1,
          tickSpacing,
          amount0: bothSupportedPair.amount0,
          amount1: bothSupportedPair.amount1,
          tickLower: tick - tickSpacing * (i + 1),
          tickUpper: tick + tickSpacing * (i + 1),
        };
        await mintLpAsPool(nonfungiblePositionManager.address, poolLogicProxy, manager, mintSettings);
        tokenId = await nonfungiblePositionManager.tokenOfOwnerByIndex(poolLogicProxy.address, 0);
        //approve for staking in gauge
        approveABI = iERC721.encodeFunctionData("approve", [bothSupportedPair.gauge, tokenId]);
        await poolLogicProxy.connect(manager).execTransaction(nonfungiblePositionManager.address, approveABI);

        const depositTx = iVelodromeCLGauge.encodeFunctionData("deposit(uint256)", [tokenId]);

        await poolLogicProxy.connect(manager).execTransaction(bothSupportedPair.gauge, depositTx);
        tokenIds.push(tokenId);
      }

      await ethers.provider.send("evm_increaseTime", [3600 * 24 * 3]); // 3 days
      await ethers.provider.send("evm_mine", []);
    });

    utils.beforeAfterReset(beforeEach, afterEach);

    describe("position handling", () => {
      it("Can mint a position after burning", async () => {
        const withdrawTx = iVelodromeCLGauge.encodeFunctionData("withdraw", [tokenIds[0]]);
        await poolLogicProxy.connect(manager).execTransaction(bothSupportedPair.gauge, withdrawTx);
        const position = await nonfungiblePositionManager.positions(tokenIds[0]);
        const decreaseLiquidityABI = iNonfungiblePositionManager.encodeFunctionData("decreaseLiquidity", [
          [tokenIds[0], position.liquidity, 0, 0, deadLine],
        ]);
        const collectABI = iNonfungiblePositionManager.encodeFunctionData("collect", [
          [tokenIds[0], poolLogicProxy.address, units(10000), units(10000)],
        ]);
        const burnABI = iNonfungiblePositionManager.encodeFunctionData("burn", [tokenIds[0]]);
        const multicallABI = iMulticall.encodeFunctionData("multicall", [[decreaseLiquidityABI, collectABI, burnABI]]);
        await poolLogicProxy.connect(manager).execTransaction(nonfungiblePositionManager.address, multicallABI);

        const tickSpacing = bothSupportedPair.tickSpacing;
        const tick = await getCurrentTick(factory, bothSupportedPair);
        const mintSettings: VelodromeCLMintSettings = {
          token0: bothSupportedPair.token0,
          token1: bothSupportedPair.token1,
          tickSpacing,
          amount0: bothSupportedPair.amount0,
          amount1: bothSupportedPair.amount1,
          tickLower: tick - tickSpacing * 3,
          tickUpper: tick + tickSpacing * 3,
        };
        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
        await mintLpAsPool(nonfungiblePositionManager.address, poolLogicProxy, manager, mintSettings);
        checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore, 0.000001);
      });
    });

    describe("withdrawProcessing", () => {
      it("Pool has expected funds after withdraw", async () => {
        let totalLiquityBefore = ethers.BigNumber.from(0);
        for (const tokenId of tokenIds) {
          totalLiquityBefore = totalLiquityBefore.add((await nonfungiblePositionManager.positions(tokenId)).liquidity);
        }
        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
        // withdraw half
        await poolLogicProxy.withdraw((await poolLogicProxy.balanceOf(logicOwner.address)).div(2));
        let totalLiquityAfter = ethers.BigNumber.from(0);
        for (const tokenId of tokenIds) {
          totalLiquityAfter = totalLiquityAfter.add((await nonfungiblePositionManager.positions(tokenId)).liquidity);
        }
        checkAlmostSame(totalLiquityAfter, totalLiquityBefore.div(2), 0.00001);
        checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore.div(2), 0.00001);
      });
      it("Pool with staked and unstaked position has expected funds after withdraw", async () => {
        const withdrawTx = iVelodromeCLGauge.encodeFunctionData("withdraw", [tokenIds[0]]);
        await poolLogicProxy.connect(manager).execTransaction(bothSupportedPair.gauge, withdrawTx);
        let totalLiquityBefore = ethers.BigNumber.from(0);
        for (const tokenId of tokenIds) {
          totalLiquityBefore = totalLiquityBefore.add((await nonfungiblePositionManager.positions(tokenId)).liquidity);
        }
        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
        // withdraw half
        await poolLogicProxy.withdraw((await poolLogicProxy.balanceOf(logicOwner.address)).div(2));
        let totalLiquityAfter = ethers.BigNumber.from(0);
        for (const tokenId of tokenIds) {
          totalLiquityAfter = totalLiquityAfter.add((await nonfungiblePositionManager.positions(tokenId)).liquidity);
        }
        checkAlmostSame(totalLiquityAfter, totalLiquityBefore.div(2), 0.00001);
        checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore.div(2), 0.00001);
      });
    });
    it("Pool receives expected rewards", async () => {
      const gauge = await ethers.getContractAt("IVelodromeCLGauge", bothSupportedPair.gauge);
      let totalReward = ethers.BigNumber.from(0);
      for (const tokenId of tokenIds) {
        const claimAmount = await gauge.earned(poolLogicProxy.address, tokenId);
        const rewards = await gauge.rewards(tokenId);
        totalReward = totalReward.add(claimAmount).add(rewards);
      }
      // withdraw half
      await poolLogicProxy.withdraw((await poolLogicProxy.balanceOf(logicOwner.address)).div(2));
      const poolRewardBalance = await PROTOCOL_TOKEN.balanceOf(poolLogicProxy.address);
      const withdrawerRewardBalance = await PROTOCOL_TOKEN.balanceOf(logicOwner.address);
      checkAlmostSame(poolRewardBalance.add(withdrawerRewardBalance), totalReward, 0.05);
      checkAlmostSame(await PROTOCOL_TOKEN.balanceOf(poolLogicProxy.address), totalReward.div(2), 0.05);
      checkAlmostSame(await PROTOCOL_TOKEN.balanceOf(logicOwner.address), totalReward.div(2), 0.05);
    });
    it("Pool with staked and unstaked position has expected funds after withdraw", async () => {
      const withdrawTx = iVelodromeCLGauge.encodeFunctionData("withdraw", [tokenIds[0]]);
      await poolLogicProxy.connect(manager).execTransaction(bothSupportedPair.gauge, withdrawTx);
      let totalLiquityBefore = ethers.BigNumber.from(0);
      for (const tokenId of tokenIds) {
        totalLiquityBefore = totalLiquityBefore.add((await nonfungiblePositionManager.positions(tokenId)).liquidity);
      }
      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
      // withdraw half
      await poolLogicProxy.withdraw((await poolLogicProxy.balanceOf(logicOwner.address)).div(2));
      let totalLiquityAfter = ethers.BigNumber.from(0);
      for (const tokenId of tokenIds) {
        totalLiquityAfter = totalLiquityAfter.add((await nonfungiblePositionManager.positions(tokenId)).liquidity);
      }
      checkAlmostSame(totalLiquityAfter, totalLiquityBefore.div(2), 0.00001);
      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore.div(2), 0.00001);
    });
  });
};
