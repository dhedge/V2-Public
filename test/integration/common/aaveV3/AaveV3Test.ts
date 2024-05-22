import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { expect } from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { checkAlmostSame, units } from "../../../testHelpers";
import {
  IAaveIncentivesControllerV3__factory,
  IERC20,
  ILendingPool__factory,
  PoolFactory,
  PoolLogic,
  PoolManagerLogic,
} from "../../../../types";
import { createFund } from "../../utils/createFund";
import { approveToken, getAccountToken } from "../../utils/getAccountTokens";
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
    let USDC: IERC20, DAI: IERC20, AMUSDC: IERC20;
    let logicOwner: SignerWithAddress, manager: SignerWithAddress;
    let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;

    before(async () => {
      deployments = await deployBackboneContracts(testParams);
      await deployAaveV3TestInfrastructure(deployments, testParams);

      poolFactory = deployments.poolFactory;
      logicOwner = deployments.owner;
      manager = deployments.manager;

      DAI = deployments.assets.DAI;
      USDC = deployments.assets.USDC;
      AMUSDC = <IERC20>await ethers.getContractAt(IERC20Path, testParams.aTokens.usdc);

      const funds = await createFund(poolFactory, logicOwner, manager, [
        { asset: USDC.address, isDeposit: true },
        { asset: testParams.assets.weth, isDeposit: true },
        { asset: testParams.assets.usdt, isDeposit: false },
      ]);
      poolLogicProxy = funds.poolLogicProxy;
      poolManagerLogicProxy = funds.poolManagerLogicProxy;

      await getAccountToken(units(100000, 6), logicOwner.address, USDC.address, testParams.assetsBalanceOfSlot.usdc);

      await USDC.approve(poolLogicProxy.address, units(20000, 6));
      await poolLogicProxy.deposit(USDC.address, units(20000, 6));
    });

    utils.beforeAfterReset(beforeEach, afterEach);
    utils.beforeAfterReset(before, after);

    it("Should not be able to borrow non lending enabled assets", async () => {
      // assert usdt is non lending
      expect(await deployments.assetHandler.assetTypes(testParams.assets.usdt)).to.equal(0);

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
        testParams.assets.usdt,
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

    it("Should be able to deposit usdc and receive amusdc", async () => {
      // Pool balance: 2M USDC
      const amount = units(10000, 6);

      let depositABI = iLendingPool.encodeFunctionData("deposit", [USDC.address, amount, poolLogicProxy.address, 0]);

      await expect(
        poolLogicProxy.connect(manager).execTransaction(ethers.constants.AddressZero, depositABI),
      ).to.be.revertedWith("non-zero address is required");

      await expect(
        poolLogicProxy.connect(manager).execTransaction(poolLogicProxy.address, depositABI),
      ).to.be.revertedWith("invalid transaction");

      // add supported assets
      await poolManagerLogicProxy
        .connect(manager)
        .changeAssets([{ asset: testParams.lendingPool, isDeposit: false }], []);

      // dai is not enabled in this pool
      depositABI = iLendingPool.encodeFunctionData("deposit", [DAI.address, amount, poolLogicProxy.address, 0]);
      await expect(
        poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, depositABI),
      ).to.be.revertedWith("unsupported deposit asset");

      depositABI = iLendingPool.encodeFunctionData("deposit", [
        testParams.assets.usdt,
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
      await expect(poolLogicProxy.connect(manager).execTransaction(USDC.address, depositABI)).to.be.revertedWith(
        "invalid transaction",
      );

      await expect(
        poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, depositABI),
      ).to.be.revertedWith("ERC20: transfer amount exceeds allowance");

      const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
      const amusdcBalanceBefore = await AMUSDC.balanceOf(poolLogicProxy.address);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      expect(usdcBalanceBefore).to.be.equal(units(20000, 6));
      expect(amusdcBalanceBefore).to.be.equal(0);

      // approve .usdc
      const approveABI = iERC20.encodeFunctionData("approve", [testParams.lendingPool, amount]);
      await poolLogicProxy.connect(manager).execTransaction(USDC.address, approveABI);

      // deposit
      await poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, depositABI);

      const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
      const amusdcBalanceAfter = await AMUSDC.balanceOf(poolLogicProxy.address);
      expect(usdcBalanceAfter).to.be.equal(amount);
      checkAlmostSame(amusdcBalanceAfter, amount);
      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
    });

    it("Should be able to supply and borrow assetType 14", async () => {
      await poolManagerLogicProxy.connect(manager).changeAssets(
        [
          { asset: testParams.lendingPool, isDeposit: false },
          { asset: testParams.assets.usdt, isDeposit: true },
        ],
        [],
      );
      const amount = units(10000, 6);
      await getAccountToken(amount, logicOwner.address, testParams.assets.usdt, testParams.assetsBalanceOfSlot.usdt);
      await approveToken(logicOwner, poolLogicProxy.address, testParams.assets.usdt, amount);
      await poolLogicProxy.deposit(testParams.assets.usdt, amount);
      // approve usdt for aave
      const approveABI = iERC20.encodeFunctionData("approve", [testParams.lendingPool, amount]);
      await poolLogicProxy.connect(manager).execTransaction(testParams.assets.usdt, approveABI);

      const depositABI = iLendingPool.encodeFunctionData("deposit", [
        testParams.assets.usdt,
        amount,
        poolLogicProxy.address,
        0,
      ]);
      await expect(
        poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, depositABI),
      ).to.be.revertedWith("not lending enabled");

      // Change USDT to type 14
      const usdAgg = await deployments.assetHandler.priceAggregators(testParams.assets.usdt);
      await deployments.assetHandler.addAsset(testParams.assets.usdt, AssetType["Synthetix + LendingEnabled"], usdAgg);

      await poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, depositABI);

      const setReserveFalseAbi = iLendingPool.encodeFunctionData("setUserUseReserveAsCollateral", [
        testParams.assets.usdt,
        false,
      ]);
      await poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, setReserveFalseAbi);

      const setReserveTrueAbi = iLendingPool.encodeFunctionData("setUserUseReserveAsCollateral", [
        testParams.assets.usdt,
        true,
      ]);
      await poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, setReserveTrueAbi);

      const borrowABI = iLendingPool.encodeFunctionData("borrow", [
        testParams.assets.usdt,
        // We can only borrow a fraction of the collateral
        amount.div(3),
        2,
        0,
        poolLogicProxy.address,
      ]);

      poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, borrowABI);
    });

    it("Includes assetType 14 debt and collateral in balance", async () => {
      await poolManagerLogicProxy.connect(manager).changeAssets(
        [
          { asset: testParams.lendingPool, isDeposit: false },
          { asset: testParams.assets.usdt, isDeposit: true },
        ],
        [],
      );
      const amount = units(10000, 6);
      await getAccountToken(amount, logicOwner.address, testParams.assets.usdt, testParams.assetsBalanceOfSlot.usdt);
      await approveToken(logicOwner, poolLogicProxy.address, testParams.assets.usdt, amount);
      await poolLogicProxy.deposit(testParams.assets.usdt, amount);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
      // approve usdt for aave
      const approveABI = iERC20.encodeFunctionData("approve", [testParams.lendingPool, amount]);
      await poolLogicProxy.connect(manager).execTransaction(testParams.assets.usdt, approveABI);

      const depositABI = iLendingPool.encodeFunctionData("deposit", [
        testParams.assets.usdt,
        amount,
        poolLogicProxy.address,
        0,
      ]);

      // Change USDT to type 14
      const usdAgg = await deployments.assetHandler.priceAggregators(testParams.assets.usdt);
      await deployments.assetHandler.addAsset(testParams.assets.usdt, AssetType["Synthetix + LendingEnabled"], usdAgg);

      await poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, depositABI);

      const borrowABI = iLendingPool.encodeFunctionData("borrow", [
        testParams.assets.usdt,
        // We can only borrow a fraction of the collateral
        amount.div(3),
        2,
        0,
        poolLogicProxy.address,
      ]);

      poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, borrowABI);

      expect(totalFundValueBefore).to.be.closeTo(
        await poolManagerLogicProxy.totalFundValue(),
        totalFundValueBefore.div(10000),
      );
    });

    describe("after deposit to aave", () => {
      beforeEach(async () => {
        // add supported assets
        await poolManagerLogicProxy
          .connect(manager)
          .changeAssets([{ asset: testParams.lendingPool, isDeposit: false }], []);

        const amount = units(10000, 6);

        // approve .usdc
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

      it("Should be able to withdraw amusdc and receive usdc", async () => {
        // Pool balance: 0.8M USDC, 1M amUSDC, $0.2M in WETH
        const amount = units(5000, 6);

        let withdrawABI = iLendingPool.encodeFunctionData("withdraw", [USDC.address, amount, poolLogicProxy.address]);

        await expect(
          poolLogicProxy.connect(manager).execTransaction(ethers.constants.AddressZero, withdrawABI),
        ).to.be.revertedWith("non-zero address is required");

        await expect(
          poolLogicProxy.connect(manager).execTransaction(poolLogicProxy.address, withdrawABI),
        ).to.be.revertedWith("invalid transaction");

        withdrawABI = iLendingPool.encodeFunctionData("withdraw", [
          testParams.aTokens.usdt,
          amount,
          poolLogicProxy.address,
        ]);
        await expect(
          poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, withdrawABI),
        ).to.be.revertedWith("unsupported withdraw asset");
        withdrawABI = iLendingPool.encodeFunctionData("withdraw", [USDC.address, amount, USDC.address]);
        await expect(
          poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, withdrawABI),
        ).to.be.revertedWith("recipient is not pool");

        withdrawABI = iLendingPool.encodeFunctionData("withdraw", [USDC.address, amount, poolLogicProxy.address]);
        await expect(poolLogicProxy.connect(manager).execTransaction(USDC.address, withdrawABI)).to.be.revertedWith(
          "invalid transaction",
        );

        const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
        const amusdcBalanceBefore = await AMUSDC.balanceOf(poolLogicProxy.address);

        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

        // withdraw
        await poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, withdrawABI);

        const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
        const amusdcBalanceAfter = await AMUSDC.balanceOf(poolLogicProxy.address);
        checkAlmostSame(ethers.BigNumber.from(usdcBalanceBefore).add(amount), usdcBalanceAfter);
        checkAlmostSame(ethers.BigNumber.from(amusdcBalanceBefore).sub(amount), amusdcBalanceAfter);

        checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
      });

      it("Should be able to set reserve as collateral", async () => {
        // Pool balance: 1.5M USDC
        // Aave balance: 0.5M amUSDC

        const lendingPool = ILendingPool__factory.connect(testParams.lendingPool, logicOwner);

        let abi = iLendingPool.encodeFunctionData("setUserUseReserveAsCollateral", [DAI.address, true]);
        await expect(poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, abi)).to.be.revertedWith(
          "unsupported asset",
        );

        abi = iLendingPool.encodeFunctionData("setUserUseReserveAsCollateral", [testParams.assets.weth, true]);
        await expect(poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, abi)).to.be.revertedWith(
          "43",
        );

        abi = iLendingPool.encodeFunctionData("setUserUseReserveAsCollateral", [USDC.address, false]);
        await poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, abi);

        const userConfigBefore = await lendingPool.getUserConfiguration(poolLogicProxy.address);

        abi = iLendingPool.encodeFunctionData("setUserUseReserveAsCollateral", [USDC.address, true]);
        await poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, abi);

        const userConfigAfter = await lendingPool.getUserConfiguration(poolLogicProxy.address);
        expect(userConfigBefore).to.be.not.equal(userConfigAfter);
      });

      it("Should be able to withdraw 20%", async () => {
        // Pool balance: 1M USDC
        // Aave balance: 1M amUSDC

        // Withdraw 20%
        const withdrawAmount = units(4000);

        const usdcBalanceBefore = ethers.BigNumber.from(await USDC.balanceOf(poolLogicProxy.address));
        const totalFundValueBefore = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());
        const userUsdcBalanceBefore = await USDC.balanceOf(logicOwner.address);

        await ethers.provider.send("evm_increaseTime", [86400]);
        await poolLogicProxy.withdraw(withdrawAmount);

        checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore.mul(80).div(100));
        const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
        checkAlmostSame(usdcBalanceAfter, usdcBalanceBefore.sub(units(2000, 6)));
        const userUsdcBalanceAfter = await USDC.balanceOf(logicOwner.address);
        checkAlmostSame(userUsdcBalanceAfter, userUsdcBalanceBefore.add(units(2000, 6)).add(units(2000, 6)));
      });

      it("Should be able to borrow DAI", async function () {
        if (!testParams.aTokens.dai) {
          console.log("DAI is not in aave, skipping test");
          return this.skip();
        }
        // Pool balance: 1M USDC
        // Aave balance: 1M amUSDC

        const amount = units(2500).toString();

        let borrowABI = iLendingPool.encodeFunctionData("borrow", [DAI.address, amount, 2, 0, poolLogicProxy.address]);

        await expect(
          poolLogicProxy.connect(manager).execTransaction(ethers.constants.AddressZero, borrowABI),
        ).to.be.revertedWith("non-zero address is required");

        await expect(
          poolLogicProxy.connect(manager).execTransaction(poolLogicProxy.address, borrowABI),
        ).to.be.revertedWith("invalid transaction");

        await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: DAI.address, isDeposit: false }], []);

        borrowABI = iLendingPool.encodeFunctionData("borrow", [DAI.address, amount, 2, 0, USDC.address]);
        await expect(
          poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, borrowABI),
        ).to.be.revertedWith("recipient is not pool");

        borrowABI = iLendingPool.encodeFunctionData("borrow", [DAI.address, amount, 2, 0, poolLogicProxy.address]);
        await expect(poolLogicProxy.connect(manager).execTransaction(DAI.address, borrowABI)).to.be.revertedWith(
          "invalid transaction",
        );

        const daiBalanceBefore = await DAI.balanceOf(poolLogicProxy.address);

        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

        expect(daiBalanceBefore).to.be.equal(0);

        // borrow
        await poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, borrowABI);

        borrowABI = iLendingPool.encodeFunctionData("borrow", [USDC.address, amount, 2, 0, poolLogicProxy.address]);
        await expect(
          poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, borrowABI),
        ).to.be.revertedWith("borrowing asset exists");

        const daiBalanceAfter = await DAI.balanceOf(poolLogicProxy.address);
        expect(daiBalanceAfter).to.be.equal(units(2500));

        checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
      });

      describe("after borrow from aave", () => {
        beforeEach(async function () {
          if (!testParams.aTokens.dai) {
            console.log("DAI is not in aave, skipping test");
            return this.skip();
          }

          // add supported assets
          await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: DAI.address, isDeposit: false }], []);

          const amount = units(2500).toString();
          const borrowABI = iLendingPool.encodeFunctionData("borrow", [
            DAI.address,
            amount,
            2,
            0,
            poolLogicProxy.address,
          ]);
          await poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, borrowABI);
        });

        it("Should be able to repay DAI", async () => {
          // Pool balance: 1M USDC, 0.25M DAI
          // Aave balance: 1M amUSDC, 0.25M debtDAI

          const amount = units(1000);

          let repayABI;

          repayABI = iLendingPool.encodeFunctionData("repay", [
            testParams.aTokens.dai,
            amount,
            2,
            poolLogicProxy.address,
          ]);
          await expect(
            poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, repayABI),
          ).to.be.revertedWith("unsupported repay asset");

          repayABI = iLendingPool.encodeFunctionData("repay", [DAI.address, amount, 2, USDC.address]);
          await expect(
            poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, repayABI),
          ).to.be.revertedWith("recipient is not pool");

          repayABI = iLendingPool.encodeFunctionData("repay", [DAI.address, amount, 2, poolLogicProxy.address]);
          await expect(poolLogicProxy.connect(manager).execTransaction(DAI.address, repayABI)).to.be.revertedWith(
            "invalid transaction",
          );

          await expect(poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, repayABI)).to.be
            .reverted;

          // approve dai
          const approveABI = iERC20.encodeFunctionData("approve", [testParams.lendingPool, amount]);
          await poolLogicProxy.connect(manager).execTransaction(DAI.address, approveABI);

          const daiBalanceBefore = await DAI.balanceOf(poolLogicProxy.address);
          expect(daiBalanceBefore).to.be.equal(units(2500));

          const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

          // repay
          await poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, repayABI);

          const daiBalanceAfter = await DAI.balanceOf(poolLogicProxy.address);
          expect(daiBalanceAfter).to.be.equal(units(1500));

          checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
        });

        it("Should be able to repayWith aDAI", async () => {
          // Pool balance: 1M USDC, 0.25M DAI
          // Aave balance: 1M amUSDC, 0.25M debtDAI

          const amount = units(1000);

          let repayABI;

          repayABI = iLendingPool.encodeFunctionData("repayWithATokens", [testParams.aTokens.dai, amount, 2]);
          await expect(
            poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, repayABI),
          ).to.be.revertedWith("unsupported repay asset");

          repayABI = iLendingPool.encodeFunctionData("repayWithATokens", [DAI.address, amount, 2]);
          await expect(poolLogicProxy.connect(manager).execTransaction(DAI.address, repayABI)).to.be.revertedWith(
            "invalid transaction",
          );

          await expect(poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, repayABI)).to.be
            .reverted;

          // approve dai
          const approveABI = iERC20.encodeFunctionData("approve", [testParams.lendingPool, amount]);
          await poolLogicProxy.connect(manager).execTransaction(DAI.address, approveABI);

          const daiBalanceBefore = await DAI.balanceOf(poolLogicProxy.address);
          expect(daiBalanceBefore).to.be.equal(units(2500));

          const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

          // deposit
          const depositABI = iLendingPool.encodeFunctionData("deposit", [
            DAI.address,
            amount,
            poolLogicProxy.address,
            0,
          ]);
          await poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, depositABI);
          // repay
          await poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, repayABI);

          const daiBalanceAfter = await DAI.balanceOf(poolLogicProxy.address);
          expect(daiBalanceAfter).to.be.equal(units(1500));

          checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
        });

        it("Should be able to withdraw after borrow", async () => {
          // Pool balance: 1M USDC, 0.25 DAI
          // Aave balance: 1M amUSDC, 0.25 debtDAI

          // enable weth to check withdraw process
          await poolManagerLogicProxy
            .connect(manager)
            .changeAssets([{ asset: testParams.assets.weth, isDeposit: false }], []);

          // Withdraw 10%
          const withdrawAmount = units(2000);

          const usdcBalanceBefore = ethers.BigNumber.from(await USDC.balanceOf(logicOwner.address));
          const totalFundValueBefore = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());

          checkAlmostSame(totalFundValueBefore, units(20000));

          await ethers.provider.send("evm_increaseTime", [86400]);
          await poolLogicProxy.withdraw(withdrawAmount);

          const totalFundValueAfter = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());

          checkAlmostSame(totalFundValueAfter, totalFundValueBefore.mul(90).div(100));
          const usdcBalanceAfter = ethers.BigNumber.from(await USDC.balanceOf(logicOwner.address));
          checkAlmostSame(usdcBalanceAfter, usdcBalanceBefore.add((1200e6).toString()));
        });

        it("Should be able to swap borrow rate mode", async () => {
          let swapRateABI = iLendingPool.encodeFunctionData("swapBorrowRateMode", [USDC.address, 1]);

          swapRateABI = iLendingPool.encodeFunctionData("swapBorrowRateMode", [testParams.aTokens.dai, 1]);
          await expect(
            poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, swapRateABI),
          ).to.be.revertedWith("unsupported asset");

          swapRateABI = iLendingPool.encodeFunctionData("swapBorrowRateMode", [USDC.address, 1]);
          await expect(
            poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, swapRateABI),
          ).to.be.revertedWith("41");

          swapRateABI = iLendingPool.encodeFunctionData("swapBorrowRateMode", [DAI.address, 1]);
          await expect(
            poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, swapRateABI),
          ).to.be.revertedWith("41");

          swapRateABI = iLendingPool.encodeFunctionData("swapBorrowRateMode", [DAI.address, 2]);
          await expect(
            poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, swapRateABI),
          ).to.be.revertedWith("31");
        });

        it("Should be able to rebalance stable borrow rate", async () => {
          let rebalanceAPI;

          rebalanceAPI = iLendingPool.encodeFunctionData("rebalanceStableBorrowRate", [
            testParams.aTokens.dai,
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
            DAI.address,
            poolLogicProxy.address,
          ]);
          await expect(
            poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, rebalanceAPI),
          ).to.be.revertedWith("44");
        });

        it("Should be able to claim rewards", async function () {
          if (
            !testParams.incentivesController ||
            !testParams.rewardToken ||
            !testParams.aTokens.dai ||
            !testParams.variableDebtTokens.dai
          ) {
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

            await ethers.provider.send("evm_increaseTime", [3600 * 24 * 10]); // add 10 days
            await ethers.provider.send("evm_mine", []);

            const remainingRewardsBefore = await incentivesController.getUserRewards(
              [
                testParams.aTokens.dai,
                testParams.aTokens.usdc,
                testParams.aTokens.usdt,
                testParams.variableDebtTokens.dai,
              ],
              poolLogicProxy.address,
              testParams.rewardToken,
            );
            if (remainingRewardsBefore.eq(0)) {
              console.log("No rewards.");
              this.skip();
            }

            let claimRewardsData = iAaveIncentivesController.encodeFunctionData("claimRewards", [
              [
                testParams.aTokens.dai,
                testParams.aTokens.usdc,
                testParams.aTokens.usdt,
                testParams.variableDebtTokens.dai,
              ],
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
              [
                testParams.aTokens.dai,
                testParams.aTokens.usdc,
                testParams.aTokens.usdt,
                testParams.variableDebtTokens.dai,
              ],
              remainingRewardsBefore,
              logicOwner.address, // wrong recipient
              testParams.rewardToken,
            ]);

            await expect(
              poolLogicProxy.connect(manager).execTransaction(incentivesController.address, claimRewardsData),
            ).to.be.revertedWith("recipient is not pool");

            claimRewardsData = iAaveIncentivesController.encodeFunctionData("claimRewards", [
              [
                testParams.aTokens.dai,
                testParams.aTokens.usdc,
                testParams.aTokens.usdt,
                testParams.variableDebtTokens.dai,
              ],
              remainingRewardsBefore,
              poolLogicProxy.address,
              testParams.rewardToken,
            ]);

            const rewardBalanceBefore = await REWARDTOKEN.balanceOf(poolLogicProxy.address);
            const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

            await poolLogicProxy.connect(manager).execTransaction(incentivesController.address, claimRewardsData);

            const remainingRewardsAfter = await incentivesController.getUserRewards(
              [
                testParams.aTokens.dai,
                testParams.aTokens.usdc,
                testParams.aTokens.usdt,
                testParams.variableDebtTokens.dai,
              ],
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
            DAI.address,
            testParams.assetsBalanceOfSlot.dai,
          );
          await expect(poolManagerLogicProxy.connect(manager).changeAssets([], [DAI.address])).to.revertedWith(
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
