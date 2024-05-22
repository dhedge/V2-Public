import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { expect } from "chai";

import { units } from "../../../testHelpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { IERC20, PoolFactory, PoolLogic, PoolManagerLogic } from "../../../../types";
import { createFund } from "../../utils/createFund";
import { getAccountToken } from "../../utils/getAccountTokens";
import { utils } from "../../utils/utils";
import { IBackboneDeployments, deployBackboneContracts } from "../../utils/deployContracts/deployBackboneContracts";
import {
  deployVelodromeV2Infrastructure,
  iERC20,
  iVelodromeGauge,
  iVelodromeRouter,
  IVelodromeV2TestParams,
} from "./velodromeV2TestDeploymentHelpers";

export const runTests = (testParams: IVelodromeV2TestParams) => {
  const { protocolToken, STABLE_USDC_DAI, router, VARIABLE_WETH_USDC, assets, assetsBalanceOfSlot } = testParams;

  describe("VelodromeV2GaugeContractGuard Test", () => {
    let deployments: IBackboneDeployments;
    let USDC: IERC20, DAI: IERC20, VELO: IERC20, VELODROME_USDC_DAI: IERC20;
    let logicOwner: SignerWithAddress, manager: SignerWithAddress, userNotPool: SignerWithAddress;
    let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
    let lpAmount: BigNumber;

    before(async () => {
      deployments = await deployBackboneContracts(testParams);
      const { USDC_DAI, PROTOCOL_TOKEN } = await deployVelodromeV2Infrastructure(deployments, testParams);

      manager = deployments.manager;
      logicOwner = deployments.owner;
      userNotPool = deployments.user;
      poolFactory = deployments.poolFactory;

      USDC = deployments.assets.USDC;
      DAI = deployments.assets.DAI;
      VELO = PROTOCOL_TOKEN;
      VELODROME_USDC_DAI = USDC_DAI;

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

      approveABI = iERC20.encodeFunctionData("approve", [STABLE_USDC_DAI.gaugeAddress, lpAmount]);
      await poolLogicProxy.connect(manager).execTransaction(STABLE_USDC_DAI.poolAddress, approveABI);
    });

    utils.beforeAfterReset(beforeEach, afterEach);

    describe("deposit", () => {
      it("Reverts if lp asset is not supported", async () => {
        const depositTx = iVelodromeGauge.encodeFunctionData("deposit(uint256)", [lpAmount]);

        await expect(
          poolLogicProxy.connect(manager).execTransaction(VARIABLE_WETH_USDC.gaugeAddress, depositTx),
        ).to.revertedWith("unsupported lp asset");
      });

      it("Allow deposit", async () => {
        const depositTx = iVelodromeGauge.encodeFunctionData("deposit(uint256)", [lpAmount]);

        await poolLogicProxy.connect(manager).execTransaction(STABLE_USDC_DAI.gaugeAddress, depositTx);

        expect(await VELODROME_USDC_DAI.balanceOf(poolLogicProxy.address)).to.equal(0);
      });
    });

    describe("withdraw", () => {
      beforeEach(async () => {
        const depositTx = iVelodromeGauge.encodeFunctionData("deposit(uint256)", [lpAmount]);
        await poolLogicProxy.connect(manager).execTransaction(STABLE_USDC_DAI.gaugeAddress, depositTx);
      });

      it("Reverts if lp asset is not supported", async () => {
        const withdrawTx = iVelodromeGauge.encodeFunctionData("withdraw", [lpAmount]);

        await expect(
          poolLogicProxy.connect(manager).execTransaction(VARIABLE_WETH_USDC.gaugeAddress, withdrawTx),
        ).to.revertedWith("unsupported lp asset");
      });

      it("Allow withdraw", async () => {
        const withdrawTx = iVelodromeGauge.encodeFunctionData("withdraw", [lpAmount]);

        await poolLogicProxy.connect(manager).execTransaction(STABLE_USDC_DAI.gaugeAddress, withdrawTx);

        expect(await VELODROME_USDC_DAI.balanceOf(poolLogicProxy.address)).to.equal(lpAmount);
      });
    });

    describe("getReward", () => {
      beforeEach(async () => {
        const depositTx = iVelodromeGauge.encodeFunctionData("deposit(uint256)", [lpAmount]);
        await poolLogicProxy.connect(manager).execTransaction(STABLE_USDC_DAI.gaugeAddress, depositTx);

        // increase time by 1 day
        await ethers.provider.send("evm_increaseTime", [3600 * 24]);
        await ethers.provider.send("evm_mine", []);
      });

      it("Reverts if invalid claimer", async () => {
        await poolManagerLogicProxy.connect(manager).changeAssets(
          [
            {
              asset: protocolToken,
              isDeposit: false,
            },
          ],
          [],
        );

        const getRewardParams = [userNotPool.address];
        const claimTx = iVelodromeGauge.encodeFunctionData("getReward", getRewardParams);

        await expect(
          poolLogicProxy.connect(manager).execTransaction(STABLE_USDC_DAI.gaugeAddress, claimTx),
        ).to.revertedWith("invalid claimer");
      });

      it("Allow claim", async () => {
        await poolManagerLogicProxy.connect(manager).changeAssets(
          [
            {
              asset: protocolToken,
              isDeposit: false,
            },
          ],
          [],
        );

        const getRewardParams = [poolLogicProxy.address];
        const claimTx = iVelodromeGauge.encodeFunctionData("getReward", getRewardParams);

        await poolLogicProxy.connect(manager).execTransaction(STABLE_USDC_DAI.gaugeAddress, claimTx);

        expect(await VELO.balanceOf(poolLogicProxy.address)).to.gt(0);
      });
    });
  });
};
