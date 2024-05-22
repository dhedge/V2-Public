import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { expect } from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import { checkAlmostSame, units } from "../../../testHelpers";
import { IERC20, IVelodromeV2Gauge, PoolFactory, PoolLogic, PoolManagerLogic } from "../../../../types";
import { createFund } from "../../utils/createFund";
import { getAccountToken } from "../../utils/getAccountTokens";
import { utils } from "../../utils/utils";
import { IBackboneDeployments, deployBackboneContracts } from "../../utils/deployContracts/deployBackboneContracts";
import {
  deployVelodromeV2Infrastructure,
  IVelodromeV2TestParams,
  iERC20,
  iVelodromeRouter,
  iVelodromeGauge,
} from "./velodromeV2TestDeploymentHelpers";

export const runTests = (testParams: IVelodromeV2TestParams) => {
  const { STABLE_USDC_DAI, router, assets, assetsBalanceOfSlot } = testParams;

  describe("VelodromeV2LPAssetGuard Test", () => {
    let deployments: IBackboneDeployments;
    let USDC: IERC20, DAI: IERC20, VELO: IERC20, VELODROME_USDC_DAI: IERC20;
    let VELODROME_USDC_DAI_GAUGE: IVelodromeV2Gauge;
    let logicOwner: SignerWithAddress, manager: SignerWithAddress;
    let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
    let lpAmount: BigNumber;

    before(async () => {
      deployments = await deployBackboneContracts(testParams);
      const { USDC_DAI, USDC_DAI_GAUGE, PROTOCOL_TOKEN } = await deployVelodromeV2Infrastructure(
        deployments,
        testParams,
      );

      manager = deployments.manager;
      logicOwner = deployments.owner;
      poolFactory = deployments.poolFactory;

      USDC = deployments.assets.USDC;
      DAI = deployments.assets.DAI;
      VELO = PROTOCOL_TOKEN;
      VELODROME_USDC_DAI = USDC_DAI;
      VELODROME_USDC_DAI_GAUGE = USDC_DAI_GAUGE;

      await getAccountToken(units(10000, 6), logicOwner.address, assets.usdc, assetsBalanceOfSlot.usdc);
      await getAccountToken(units(10000), logicOwner.address, assets.dai, assetsBalanceOfSlot.dai);

      const funds = await createFund(poolFactory, logicOwner, manager, [
        { asset: assets.usdc, isDeposit: true },
        { asset: assets.dai, isDeposit: true },
        { asset: STABLE_USDC_DAI.poolAddress, isDeposit: false },
      ]);
      poolLogicProxy = funds.poolLogicProxy;
      poolManagerLogicProxy = funds.poolManagerLogicProxy;

      // Deposit 200 USDC
      await USDC.approve(poolLogicProxy.address, units(200, 6));
      await poolLogicProxy.deposit(assets.usdc, units(200, 6));
      // Deposit 200 DAI
      await DAI.approve(poolLogicProxy.address, units(200));
      await poolLogicProxy.deposit(assets.dai, units(200));

      let approveABI = iERC20.encodeFunctionData("approve", [router, units(200, 6)]);
      await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);
      approveABI = iERC20.encodeFunctionData("approve", [router, units(200)]);
      await poolLogicProxy.connect(manager).execTransaction(assets.dai, approveABI);
    });

    utils.beforeAfterReset(beforeEach, afterEach);

    describe("withdrawProcessing", () => {
      beforeEach(async () => {
        const addLiquidityTx = iVelodromeRouter.encodeFunctionData("addLiquidity", [
          assets.usdc,
          assets.dai,
          STABLE_USDC_DAI.isStable,
          units(100, 6),
          units(100),
          0,
          0,
          poolLogicProxy.address,
          ethers.constants.MaxUint256,
        ]);
        await poolLogicProxy.connect(manager).execTransaction(router, addLiquidityTx);

        lpAmount = await VELODROME_USDC_DAI.balanceOf(poolLogicProxy.address);

        const approveABI = iERC20.encodeFunctionData("approve", [STABLE_USDC_DAI.gaugeAddress, lpAmount]);
        await poolLogicProxy.connect(manager).execTransaction(STABLE_USDC_DAI.poolAddress, approveABI);

        const depositABI = iVelodromeGauge.encodeFunctionData("deposit(uint256)", [lpAmount]);
        await poolLogicProxy.connect(manager).execTransaction(STABLE_USDC_DAI.gaugeAddress, depositABI);

        await poolFactory.setExitCooldown(0);
        await deployments.assetHandler.setChainlinkTimeout(86400 * 7); // 7 days expiry
        await ethers.provider.send("evm_increaseTime", [3600 * 24 * 3]); // 3 days
        await ethers.provider.send("evm_mine", []);
      });

      it("Pool has expected funds after withdraw", async () => {
        const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
        const daiBalanceBefore = await DAI.balanceOf(poolLogicProxy.address);
        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
        const gaugeBalanceBefore = await VELODROME_USDC_DAI_GAUGE.balanceOf(poolLogicProxy.address);

        // withdraw half
        await poolLogicProxy.withdraw((await poolLogicProxy.balanceOf(logicOwner.address)).div(2));

        // includes additional rewards, hence 0.05% threshold
        checkAlmostSame(await USDC.balanceOf(poolLogicProxy.address), usdcBalanceBefore.div(2), 0.05); // includes additional rewards, hence 0.05% threshold
        checkAlmostSame(await DAI.balanceOf(poolLogicProxy.address), daiBalanceBefore.div(2), 0.05); // includes additional rewards, hence 0.05% threshold
        checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore.div(2), 0.05); // includes additional rewards, hence 0.05% threshold
        checkAlmostSame(
          await VELODROME_USDC_DAI_GAUGE.balanceOf(poolLogicProxy.address),
          gaugeBalanceBefore.div(2),
          0.05,
        );
      });

      it("Pool receives expected rewards", async () => {
        const claimAmount = await VELODROME_USDC_DAI_GAUGE.earned(poolLogicProxy.address);
        expect(claimAmount).to.gt(0);

        // withdraw half
        await poolLogicProxy.withdraw((await poolLogicProxy.balanceOf(logicOwner.address)).div(2));

        checkAlmostSame(await VELO.balanceOf(poolLogicProxy.address), claimAmount.div(2), 0.05);
      });

      it("Withdrawer receives their portion of LP Tokens and Rewards", async () => {
        const claimAmount = await VELODROME_USDC_DAI_GAUGE.earned(poolLogicProxy.address);
        expect(claimAmount).to.gt(0);

        // withdraw half
        await poolLogicProxy.withdraw((await poolLogicProxy.balanceOf(logicOwner.address)).div(2));
        checkAlmostSame(await VELODROME_USDC_DAI.balanceOf(logicOwner.address), lpAmount.div(2), 0.05);
        checkAlmostSame(await VELO.balanceOf(logicOwner.address), claimAmount.div(2), 0.05);
      });
    });

    describe("getBalance", () => {
      it("Prices underlying LP token correctly", async () => {
        let totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

        const addLiquidityTx = iVelodromeRouter.encodeFunctionData("addLiquidity", [
          assets.usdc,
          assets.dai,
          STABLE_USDC_DAI.isStable,
          units(100, 6),
          units(100),
          0,
          0,
          poolLogicProxy.address,
          ethers.constants.MaxUint256,
        ]);
        await poolLogicProxy.connect(manager).execTransaction(router, addLiquidityTx);

        // price change between chainlink & amm, threshold
        checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore, 0.05);

        lpAmount = await VELODROME_USDC_DAI.balanceOf(poolLogicProxy.address);

        totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
        const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
        const daiBalanceBefore = await DAI.balanceOf(poolLogicProxy.address);

        const approveABI = iERC20.encodeFunctionData("approve", [STABLE_USDC_DAI.gaugeAddress, lpAmount]);
        await poolLogicProxy.connect(manager).execTransaction(STABLE_USDC_DAI.poolAddress, approveABI);

        const depositABI = iVelodromeGauge.encodeFunctionData("deposit(uint256)", [lpAmount.div(2)]);
        await poolLogicProxy.connect(manager).execTransaction(STABLE_USDC_DAI.gaugeAddress, depositABI);

        expect(await VELODROME_USDC_DAI.balanceOf(poolLogicProxy.address)).to.be.closeTo(lpAmount.div(2), 1);
        expect(await USDC.balanceOf(poolLogicProxy.address)).to.be.eq(usdcBalanceBefore);
        expect(await DAI.balanceOf(poolLogicProxy.address)).to.be.eq(daiBalanceBefore);
        expect(await poolManagerLogicProxy.totalFundValue()).to.equal(totalFundValueBefore);
      });

      it("Includes unclaimed rewards in Price", async () => {
        const addLiquidityTx = iVelodromeRouter.encodeFunctionData("addLiquidity", [
          assets.usdc,
          assets.dai,
          STABLE_USDC_DAI.isStable,
          units(100, 6),
          units(100),
          0,
          0,
          poolLogicProxy.address,
          ethers.constants.MaxUint256,
        ]);
        await poolLogicProxy.connect(manager).execTransaction(router, addLiquidityTx);

        lpAmount = await VELODROME_USDC_DAI.balanceOf(poolLogicProxy.address);

        const approveABI = iERC20.encodeFunctionData("approve", [STABLE_USDC_DAI.gaugeAddress, lpAmount]);
        await poolLogicProxy.connect(manager).execTransaction(STABLE_USDC_DAI.poolAddress, approveABI);

        const depositABI = iVelodromeGauge.encodeFunctionData("deposit(uint256)", [lpAmount]);
        await poolLogicProxy.connect(manager).execTransaction(STABLE_USDC_DAI.gaugeAddress, depositABI);

        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

        await deployments.assetHandler.setChainlinkTimeout(86400 * 7); // 7 days expiry
        await ethers.provider.send("evm_increaseTime", [3600 * 24]);
        await ethers.provider.send("evm_mine", []);

        const claimAmount = await VELODROME_USDC_DAI_GAUGE.earned(poolLogicProxy.address);
        expect(claimAmount).to.gt(0);
        expect(await poolManagerLogicProxy.totalFundValue()).to.closeTo(
          totalFundValueBefore.add(
            await poolManagerLogicProxy["assetValue(address,uint256)"](VELO.address, claimAmount),
          ),
          await poolManagerLogicProxy["assetValue(address,uint256)"](VELO.address, claimAmount.div(1000)),
        );
      });
    });
  });
};
