import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { expect } from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { checkAlmostSame, units } from "../../../testHelpers";
import {
  IAaveIncentivesControllerV3__factory,
  IAaveV3Pool,
  IERC20,
  PoolFactory,
  PoolLogic,
  PoolManagerLogic,
} from "../../../../types";
import { createFund } from "../../utils/createFund";
import { getAccountToken } from "../../utils/getAccountTokens";
import {
  IBackboneDeployments,
  deployBackboneContracts,
  iERC20,
  IERC20Path,
} from "../../utils/deployContracts/deployBackboneContracts";
import { utils } from "../../utils/utils";
import { AssetType } from "../../../../deployment/upgrade/jobs/assetsJob";
import { deployAaveV3TestInfrastructure, iLendingPool, IAaveV3TestParameters } from "./deployAaveV3TestInfrastructure";

export const testAaveV3 = (testParams: IAaveV3TestParameters) => {
  describe("Aave V3 Test", () => {
    let deployments: IBackboneDeployments;
    let USDC: IERC20, WETH: IERC20, aUSDC: IERC20;
    let logicOwner: SignerWithAddress, manager: SignerWithAddress;
    let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
    let aaveV3LendingPoolContract: IAaveV3Pool;

    before(async () => {
      deployments = await deployBackboneContracts(testParams);
      await deployAaveV3TestInfrastructure(deployments, testParams);

      poolFactory = deployments.poolFactory;
      logicOwner = deployments.owner;
      manager = deployments.manager;

      WETH = deployments.assets.WETH;
      USDC = deployments.assets.USDC;
      aaveV3LendingPoolContract = await ethers.getContractAt("IAaveV3Pool", testParams.lendingPool);
      const { aTokenAddress } = await aaveV3LendingPoolContract.getReserveData(USDC.address);
      aUSDC = <IERC20>await ethers.getContractAt(IERC20Path, aTokenAddress);

      const funds = await createFund(poolFactory, logicOwner, manager, [{ asset: USDC.address, isDeposit: true }]);
      poolLogicProxy = funds.poolLogicProxy;
      poolManagerLogicProxy = funds.poolManagerLogicProxy;

      await getAccountToken(units(100000, 6), logicOwner.address, USDC.address, testParams.assetsBalanceOfSlot.usdc);

      await USDC.approve(poolLogicProxy.address, units(20000, 6));
      await poolLogicProxy.deposit(USDC.address, units(20000, 6));
    });

    utils.beforeAfterReset(beforeEach, afterEach);

    it("Should not be able to borrow non lending enabled assets", async () => {
      // assert dai is non lending
      expect(await deployments.assetHandler.assetTypes(testParams.assets.dai)).to.equal(0);

      const amount = units(10000, 6);
      await poolManagerLogicProxy
        .connect(manager)
        .changeAssets([{ asset: testParams.lendingPool, isDeposit: false }], []);
      const depositABI = iLendingPool.encodeFunctionData("deposit", [USDC.address, amount, poolLogicProxy.address, 0]);

      // approve usdc for aave
      const approveABI = iERC20.encodeFunctionData("approve", [testParams.lendingPool, amount]);
      await poolLogicProxy.connect(manager).execTransaction(USDC.address, approveABI);
      // deposit usdc into aave
      await poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, depositABI);

      const borrowABI = iLendingPool.encodeFunctionData("borrow", [
        testParams.assets.dai,
        // We can only borrow a fraction of the collateral
        amount.div(3),
        2,
        0,
        poolLogicProxy.address,
      ]);
      // Should no be able to borrow non lending assets
      await expect(
        poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, borrowABI),
      ).to.be.revertedWith("not borrow enabled");
    });

    it("Should be able to deposit usdc and receive overlying aTokens", async () => {
      // Pool balance: 20_000 USDC
      const amount = units(10000, 6);

      let depositABI = iLendingPool.encodeFunctionData("deposit", [USDC.address, amount, poolLogicProxy.address, 0]);

      await expect(
        poolLogicProxy.connect(manager).execTransaction(poolLogicProxy.address, depositABI),
      ).to.be.revertedWith("invalid transaction");

      // add supported assets
      await poolManagerLogicProxy
        .connect(manager)
        .changeAssets([{ asset: testParams.lendingPool, isDeposit: false }], []);

      // weth is not enabled in this pool
      depositABI = iLendingPool.encodeFunctionData("deposit", [WETH.address, amount, poolLogicProxy.address, 0]);
      await expect(
        poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, depositABI),
      ).to.be.revertedWith("unsupported deposit asset");

      depositABI = iLendingPool.encodeFunctionData("deposit", [
        testParams.assets.dai,
        amount,
        poolLogicProxy.address,
        0,
      ]);
      await expect(
        poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, depositABI),
      ).to.be.revertedWith("not lending enabled");

      depositABI = iLendingPool.encodeFunctionData("deposit", [USDC.address, amount, USDC.address, 0]);
      await expect(
        poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, depositABI),
      ).to.be.revertedWith("recipient is not pool");

      depositABI = iLendingPool.encodeFunctionData("deposit", [USDC.address, amount, poolLogicProxy.address, 0]);
      await expect(
        poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, depositABI),
      ).to.be.revertedWith("ERC20: transfer amount exceeds allowance");

      const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
      const aUsdcBalanceBefore = await aUSDC.balanceOf(poolLogicProxy.address);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      expect(usdcBalanceBefore).to.be.equal(units(20000, 6));
      expect(aUsdcBalanceBefore).to.be.equal(0);

      // approve usdc
      const approveABI = iERC20.encodeFunctionData("approve", [testParams.lendingPool, amount]);
      await poolLogicProxy.connect(manager).execTransaction(USDC.address, approveABI);

      // deposit
      await poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, depositABI);

      const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
      const aUsdcBalanceAfter = await aUSDC.balanceOf(poolLogicProxy.address);

      expect(usdcBalanceAfter).to.be.equal(amount);
      checkAlmostSame(aUsdcBalanceAfter, amount, 0.001);
      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore, 0.001);
    });

    it("Should be able to supply and borrow assetType 14", async () => {
      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      await poolManagerLogicProxy.connect(manager).changeAssets(
        [
          { asset: testParams.lendingPool, isDeposit: false },
          { asset: WETH.address, isDeposit: true },
        ],
        [],
      );
      const amount = units(10000, 6);
      // approve usdc for aave
      const approveABI = iERC20.encodeFunctionData("approve", [testParams.lendingPool, amount]);
      await poolLogicProxy.connect(manager).execTransaction(USDC.address, approveABI);

      const depositABI = iLendingPool.encodeFunctionData("deposit", [USDC.address, amount, poolLogicProxy.address, 0]);

      // change usdc to type 14
      const priceAggregator = await deployments.assetHandler.priceAggregators(USDC.address);
      await deployments.assetHandler.addAsset(USDC.address, AssetType["Synthetix + LendingEnabled"], priceAggregator);
      // change weth to type 14
      const wethPriceAggregator = await deployments.assetHandler.priceAggregators(WETH.address);
      await deployments.assetHandler.addAsset(
        WETH.address,
        AssetType["Synthetix + LendingEnabled"],
        wethPriceAggregator,
      );

      await poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, depositABI);

      const setReserveFalseAbi = iLendingPool.encodeFunctionData("setUserUseReserveAsCollateral", [
        USDC.address,
        false,
      ]);
      await poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, setReserveFalseAbi);

      const setReserveTrueAbi = iLendingPool.encodeFunctionData("setUserUseReserveAsCollateral", [USDC.address, true]);
      await poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, setReserveTrueAbi);

      const borrowABI = iLendingPool.encodeFunctionData("borrow", [
        WETH.address,
        // We can only borrow a fraction of the collateral
        amount.div(3),
        2,
        0,
        poolLogicProxy.address,
      ]);

      await poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, borrowABI);

      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore, 0.001);
    });

    describe("after deposit to aave", () => {
      beforeEach(async () => {
        // add supported assets
        await poolManagerLogicProxy
          .connect(manager)
          .changeAssets([{ asset: testParams.lendingPool, isDeposit: false }], []);

        const amount = units(10000, 6);

        // approve usdc
        const approveABI = iERC20.encodeFunctionData("approve", [testParams.lendingPool, amount]);
        await poolLogicProxy.connect(manager).execTransaction(USDC.address, approveABI);

        const depositABI = iLendingPool.encodeFunctionData("deposit", [
          USDC.address,
          amount,
          poolLogicProxy.address,
          0,
        ]);

        await poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, depositABI);
      });

      it("Should be able to withdraw aUsdc and receive usdc", async () => {
        const amount = units(5000, 6);

        let withdrawABI = iLendingPool.encodeFunctionData("withdraw", [USDC.address, amount, poolLogicProxy.address]);
        await expect(
          poolLogicProxy.connect(manager).execTransaction(poolLogicProxy.address, withdrawABI),
        ).to.be.revertedWith("invalid transaction");

        withdrawABI = iLendingPool.encodeFunctionData("withdraw", [WETH.address, amount, poolLogicProxy.address]);
        await expect(
          poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, withdrawABI),
        ).to.be.revertedWith("unsupported withdraw asset");

        withdrawABI = iLendingPool.encodeFunctionData("withdraw", [USDC.address, amount, USDC.address]);
        await expect(
          poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, withdrawABI),
        ).to.be.revertedWith("recipient is not pool");

        withdrawABI = iLendingPool.encodeFunctionData("withdraw", [USDC.address, amount, poolLogicProxy.address]);

        const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
        const aUsdcBalanceBefore = await aUSDC.balanceOf(poolLogicProxy.address);
        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

        // withdraw
        await poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, withdrawABI);

        const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
        const aUsdcBalanceAfter = await aUSDC.balanceOf(poolLogicProxy.address);
        expect(usdcBalanceAfter).to.be.equal(amount.add(usdcBalanceBefore));
        checkAlmostSame(aUsdcBalanceAfter, aUsdcBalanceBefore.sub(amount), 0.001);

        checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore, 0.001);
      });

      it("Should be able to set reserve as collateral", async () => {
        let abi = iLendingPool.encodeFunctionData("setUserUseReserveAsCollateral", [testParams.assets.weth, true]);
        await expect(poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, abi)).to.be.revertedWith(
          "unsupported asset",
        );

        abi = iLendingPool.encodeFunctionData("setUserUseReserveAsCollateral", [USDC.address, false]);
        await poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, abi);

        const userConfigBefore = await aaveV3LendingPoolContract.getUserConfiguration(poolLogicProxy.address);

        abi = iLendingPool.encodeFunctionData("setUserUseReserveAsCollateral", [USDC.address, true]);
        await poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, abi);

        const userConfigAfter = await aaveV3LendingPoolContract.getUserConfiguration(poolLogicProxy.address);
        expect(userConfigBefore).to.be.not.equal(userConfigAfter);
      });

      it("Should be able to withdraw 20%", async () => {
        // Pool balance: 10000 USDC
        // Aave balance: 10000 aUSDC

        // Withdraw 20%
        const withdrawAmount = units(4000);

        const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
        const userUsdcBalanceBefore = await USDC.balanceOf(logicOwner.address);

        await utils.increaseTime(86400);

        await poolLogicProxy.withdraw(withdrawAmount);

        const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
        const userUsdcBalanceAfter = await USDC.balanceOf(logicOwner.address);
        checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore.mul(80).div(100), 0.1);
        checkAlmostSame(usdcBalanceAfter, usdcBalanceBefore.sub(units(2000, 6)), 0.01);
        checkAlmostSame(userUsdcBalanceAfter, userUsdcBalanceBefore.add(units(2000, 6)).add(units(2000, 6)), 0.001);
      });

      it("Should be able to borrow weth", async () => {
        // Pool balance: 10000 USDC
        // Aave balance: 10000 aUSDC

        const amount = units(1);

        let borrowABI = iLendingPool.encodeFunctionData("borrow", [WETH.address, amount, 2, 0, poolLogicProxy.address]);

        await expect(
          poolLogicProxy.connect(manager).execTransaction(poolLogicProxy.address, borrowABI),
        ).to.be.revertedWith("invalid transaction");

        await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: WETH.address, isDeposit: false }], []);

        borrowABI = iLendingPool.encodeFunctionData("borrow", [WETH.address, amount, 2, 0, USDC.address]);
        await expect(
          poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, borrowABI),
        ).to.be.revertedWith("recipient is not pool");

        borrowABI = iLendingPool.encodeFunctionData("borrow", [WETH.address, amount, 2, 0, poolLogicProxy.address]);

        const wethBalanceBefore = await WETH.balanceOf(poolLogicProxy.address);

        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

        expect(wethBalanceBefore).to.be.equal(0);

        // borrow
        await poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, borrowABI);

        borrowABI = iLendingPool.encodeFunctionData("borrow", [USDC.address, amount, 2, 0, poolLogicProxy.address]);
        await expect(
          poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, borrowABI),
        ).to.be.revertedWith("borrowing asset exists");

        const wethBalanceAfter = await WETH.balanceOf(poolLogicProxy.address);
        expect(wethBalanceAfter).to.be.equal(units(1));

        checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore, 0.001);
      });

      describe("after borrow from aave", () => {
        beforeEach(async () => {
          // add supported assets
          await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: WETH.address, isDeposit: false }], []);

          const amount = units(1);
          const borrowABI = iLendingPool.encodeFunctionData("borrow", [
            WETH.address,
            amount,
            2,
            0,
            poolLogicProxy.address,
          ]);
          await poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, borrowABI);
        });

        it("Should be able to repay weth", async () => {
          // Pool balance: 10000 USDC, 1 WETH
          // Aave balance: 10000 aUSDC, 1 debtWETH

          const amount = units(5, 17);

          let repayABI = iLendingPool.encodeFunctionData("repay", [
            testParams.assets.dai,
            amount,
            2,
            poolLogicProxy.address,
          ]);
          await expect(
            poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, repayABI),
          ).to.be.revertedWith("unsupported repay asset");

          repayABI = iLendingPool.encodeFunctionData("repay", [WETH.address, amount, 2, USDC.address]);
          await expect(
            poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, repayABI),
          ).to.be.revertedWith("recipient is not pool");

          repayABI = iLendingPool.encodeFunctionData("repay", [WETH.address, amount, 2, poolLogicProxy.address]);
          await expect(poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, repayABI)).to.be
            .reverted;

          // approve dai
          const approveTxData = iERC20.encodeFunctionData("approve", [testParams.lendingPool, amount]);
          await poolLogicProxy.connect(manager).execTransaction(WETH.address, approveTxData);

          const wethBalanceBefore = await WETH.balanceOf(poolLogicProxy.address);
          expect(wethBalanceBefore).to.be.equal(units(1));
          const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

          // repay
          await poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, repayABI);

          const wethBalanceAfter = await WETH.balanceOf(poolLogicProxy.address);
          expect(wethBalanceAfter).to.be.equal(units(5, 17));

          checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore, 0.001);
        });

        it("Should be able to repayWith aTokens", async () => {
          // Pool balance: 10000 USDC, 1 WETH
          // Aave balance: 10000 amUSDC, 1 debtWETH

          const amount = units(5, 17);

          let repayABI = iLendingPool.encodeFunctionData("repayWithATokens", [testParams.assets.dai, amount, 2]);
          await expect(
            poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, repayABI),
          ).to.be.revertedWith("unsupported repay asset");

          repayABI = iLendingPool.encodeFunctionData("repayWithATokens", [WETH.address, amount, 2]);
          await expect(poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, repayABI)).to.be
            .reverted;

          // approve weth
          const approveTx = iERC20.encodeFunctionData("approve", [testParams.lendingPool, amount]);
          await poolLogicProxy.connect(manager).execTransaction(WETH.address, approveTx);

          const wethBalanceBefore = await WETH.balanceOf(poolLogicProxy.address);
          expect(wethBalanceBefore).to.be.equal(units(1));

          const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

          // deposit
          const depositABI = iLendingPool.encodeFunctionData("deposit", [
            WETH.address,
            amount,
            poolLogicProxy.address,
            0,
          ]);
          await poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, depositABI);
          // repay
          await poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, repayABI);

          const wethBalanceAfter = await WETH.balanceOf(poolLogicProxy.address);
          expect(wethBalanceAfter).to.be.equal(units(5, 17));

          checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore, 0.001);
        });

        it("Should be able to withdraw after borrow", async () => {
          // Pool balance: 10000 USDC, 1 WETH
          // Aave balance: 10000 aUSDC, 1 debtWETH

          // Withdraw 10%
          const withdrawAmount = units(2000);

          const usdcBalanceBefore = await USDC.balanceOf(logicOwner.address);
          const wethBalanceBefore = await WETH.balanceOf(logicOwner.address);
          const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

          checkAlmostSame(totalFundValueBefore, units(20000), 0.1);
          expect(wethBalanceBefore).to.be.equal(0);

          await utils.increaseTime(86400);
          await poolLogicProxy.withdraw(withdrawAmount);

          const totalFundValueAfter = await poolManagerLogicProxy.totalFundValue();

          checkAlmostSame(totalFundValueAfter, totalFundValueBefore.mul(90).div(100), 0.1);
          const usdcBalanceAfter = await USDC.balanceOf(logicOwner.address);
          const wethBalanceAfter = await WETH.balanceOf(logicOwner.address);
          checkAlmostSame(usdcBalanceAfter, usdcBalanceBefore.add(1000e6), 0.001);
          expect(wethBalanceAfter).to.be.gt(units(1, 17));
        });

        it("Should be able to swap borrow rate mode", async () => {
          let swapRateABI = iLendingPool.encodeFunctionData("swapBorrowRateMode", [USDC.address, 1]);

          swapRateABI = iLendingPool.encodeFunctionData("swapBorrowRateMode", [testParams.assets.dai, 1]);
          await expect(
            poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, swapRateABI),
          ).to.be.revertedWith("unsupported asset");

          swapRateABI = iLendingPool.encodeFunctionData("swapBorrowRateMode", [USDC.address, 1]);
          await expect(
            poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, swapRateABI),
          ).to.be.revertedWith("41");

          swapRateABI = iLendingPool.encodeFunctionData("swapBorrowRateMode", [WETH.address, 1]);
          await expect(
            poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, swapRateABI),
          ).to.be.revertedWith("41");

          swapRateABI = iLendingPool.encodeFunctionData("swapBorrowRateMode", [WETH.address, 2]);
          await expect(
            poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, swapRateABI),
          ).to.be.revertedWith("only variable rate"); // can't swap from variable to stable
        });

        it("Should be able to rebalance stable borrow rate", async () => {
          let rebalanceAPI = iLendingPool.encodeFunctionData("rebalanceStableBorrowRate", [
            testParams.assets.dai,
            poolLogicProxy.address,
          ]);
          await expect(
            poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, rebalanceAPI),
          ).to.be.revertedWith("unsupported asset");

          rebalanceAPI = iLendingPool.encodeFunctionData("rebalanceStableBorrowRate", [
            USDC.address,
            testParams.assets.weth,
          ]);
          await expect(
            poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, rebalanceAPI),
          ).to.be.revertedWith("user is not pool");

          rebalanceAPI = iLendingPool.encodeFunctionData("rebalanceStableBorrowRate", [
            USDC.address,
            poolLogicProxy.address,
          ]);
          await expect(
            poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, rebalanceAPI),
          ).to.be.revertedWith("44");

          rebalanceAPI = iLendingPool.encodeFunctionData("rebalanceStableBorrowRate", [
            WETH.address,
            poolLogicProxy.address,
          ]);
          await expect(
            poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, rebalanceAPI),
          ).to.be.revertedWith("44");
        });

        it("Should be able to claim rewards", async function () {
          if (!testParams.incentivesController || !testParams.rewardToken) {
            console.log("Aave rewards not configured. Skipping test.");
            this.skip();
          } else {
            const REWARDTOKEN = await ethers.getContractAt(
              "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
              testParams.rewardToken,
            );
            const iAaveIncentivesController = new ethers.utils.Interface(IAaveIncentivesControllerV3__factory.abi);
            const incentivesController = IAaveIncentivesControllerV3__factory.connect(
              testParams.incentivesController,
              logicOwner,
            );

            await utils.increaseTime(3600 * 24 * 10); // add 10 days

            const remainingRewardsBefore = await incentivesController.getUserRewards(
              [aUSDC.address],
              poolLogicProxy.address,
              testParams.rewardToken,
            );
            if (remainingRewardsBefore.eq(0)) {
              console.log("No rewards.");
              this.skip();
            }

            let claimRewardsData = iAaveIncentivesController.encodeFunctionData("claimRewards", [
              [aUSDC.address],
              remainingRewardsBefore,
              poolLogicProxy.address,
              testParams.rewardToken,
            ]);

            await expect(
              poolLogicProxy.connect(manager).execTransaction(incentivesController.address, claimRewardsData),
            ).to.be.revertedWith("unsupported reward asset");

            // add supported assets
            await poolManagerLogicProxy
              .connect(manager)
              .changeAssets([{ asset: testParams.rewardToken, isDeposit: false }], []);

            claimRewardsData = iAaveIncentivesController.encodeFunctionData("claimRewards", [
              [aUSDC.address],
              remainingRewardsBefore,
              logicOwner.address, // wrong recipient
              testParams.rewardToken,
            ]);

            await expect(
              poolLogicProxy.connect(manager).execTransaction(incentivesController.address, claimRewardsData),
            ).to.be.revertedWith("recipient is not pool");

            claimRewardsData = iAaveIncentivesController.encodeFunctionData("claimRewards", [
              [aUSDC.address],
              remainingRewardsBefore,
              poolLogicProxy.address,
              testParams.rewardToken,
            ]);

            const rewardBalanceBefore = await REWARDTOKEN.balanceOf(poolLogicProxy.address);
            const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

            await poolLogicProxy.connect(manager).execTransaction(incentivesController.address, claimRewardsData);

            const remainingRewardsAfter = await incentivesController.getUserRewards(
              [aUSDC.address],
              poolLogicProxy.address,
              testParams.rewardToken,
            );
            expect(remainingRewardsAfter).to.lt(remainingRewardsBefore);
            const totalFundValueAfter = await poolManagerLogicProxy.totalFundValue();
            expect(totalFundValueAfter).to.be.gt(totalFundValueBefore);
            const rewardBalanceAfter = await REWARDTOKEN.balanceOf(poolLogicProxy.address);
            expect(rewardBalanceAfter).to.be.gt(rewardBalanceBefore);
          }
        });

        it("Should fail to remove asset", async () => {
          await getAccountToken(
            BigNumber.from("0"),
            poolLogicProxy.address,
            WETH.address,
            testParams.assetsBalanceOfSlot.weth,
          );
          await expect(poolManagerLogicProxy.connect(manager).changeAssets([], [WETH.address])).to.revertedWith(
            "repay Aave debt first",
          );
          await getAccountToken(
            BigNumber.from("0"),
            poolLogicProxy.address,
            USDC.address,
            testParams.assetsBalanceOfSlot.usdc,
          );
          await expect(poolManagerLogicProxy.connect(manager).changeAssets([], [USDC.address])).to.revertedWith(
            "withdraw Aave collateral first",
          );
          await expect(
            poolManagerLogicProxy.connect(manager).changeAssets([], [testParams.lendingPool]),
          ).to.revertedWith("cannot remove non-empty asset");
        });
      });
    });
  });
};
