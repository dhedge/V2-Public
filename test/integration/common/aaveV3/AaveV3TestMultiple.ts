import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { IAaveV3Pool, IERC20, PoolFactory, PoolLogic, PoolManagerLogic } from "../../../../types";
import { checkAlmostSame, units } from "../../../testHelpers";
import { createFund } from "../../utils/createFund";
import { getAccountToken } from "../../utils/getAccountTokens";
import { getBalance } from "../../utils/getAccountTokens/index";
import { utils } from "../../utils/utils";
import {
  deployBackboneContracts,
  IERC20Path,
  iERC20,
  IBackboneDeployments,
} from "../../utils/deployContracts/deployBackboneContracts";
import {
  deployAaveV3TestInfrastructure,
  IAaveV3TestParameters,
  iLendingPool,
  getComplexAssetsData,
} from "./deployAaveV3TestInfrastructure";
import { assetSetting } from "../../utils/deployContracts/getChainAssets";
import { AssetType } from "../../../../deployment/upgrade/jobs/assetsJob";

export const testAaveV3Multiple = (testParams: IAaveV3TestParameters) => {
  describe("Aave V3 Test Multiple", () => {
    let deployments: IBackboneDeployments;
    let WETH: IERC20,
      USDC: IERC20,
      borrowAsset: IERC20,
      aUSDC: IERC20,
      aWETH: IERC20,
      debtWETH: IERC20,
      debtBorrowAsset: IERC20;
    let logicOwner: SignerWithAddress, manager: SignerWithAddress;
    let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
    let aaveV3LendingPoolContract: IAaveV3Pool;

    utils.beforeAfterReset(before, after);

    before(async () => {
      deployments = await deployBackboneContracts(testParams);
      await deployAaveV3TestInfrastructure(deployments, testParams);
      await deployments.assetHandler.addAssets([
        assetSetting(testParams.borrowAsset, AssetType["Lending Enable Asset"], testParams.usdPriceFeeds.borrowAsset),
      ]);

      poolFactory = deployments.poolFactory;
      logicOwner = deployments.owner;
      manager = deployments.manager;

      WETH = deployments.assets.WETH;
      USDC = deployments.assets.USDC;
      borrowAsset = <IERC20>await ethers.getContractAt(IERC20Path, testParams.borrowAsset);
      aaveV3LendingPoolContract = await ethers.getContractAt("IAaveV3Pool", testParams.lendingPool);
      const { aTokenAddress: aUSDCAddress } = await aaveV3LendingPoolContract.getReserveData(USDC.address);
      const { aTokenAddress: aWETHAddress, variableDebtTokenAddress: varWETH } =
        await aaveV3LendingPoolContract.getReserveData(WETH.address);
      const { variableDebtTokenAddress } = await aaveV3LendingPoolContract.getReserveData(testParams.borrowAsset);
      aUSDC = <IERC20>await ethers.getContractAt(IERC20Path, aUSDCAddress);
      aWETH = <IERC20>await ethers.getContractAt(IERC20Path, aWETHAddress);
      debtWETH = <IERC20>await ethers.getContractAt(IERC20Path, varWETH);
      debtBorrowAsset = <IERC20>await ethers.getContractAt(IERC20Path, variableDebtTokenAddress);

      await getAccountToken(units(100000, 6), logicOwner.address, USDC.address, testParams.assetsBalanceOfSlot.usdc);
      await getAccountToken(units(100000), logicOwner.address, WETH.address, testParams.assetsBalanceOfSlot.weth);

      const funds = await createFund(poolFactory, logicOwner, manager, [
        { asset: USDC.address, isDeposit: true },
        { asset: WETH.address, isDeposit: true },
      ]);
      poolLogicProxy = funds.poolLogicProxy;
      poolManagerLogicProxy = funds.poolManagerLogicProxy;

      // Deposit 20000 USDC
      await USDC.approve(poolLogicProxy.address, units(20000, 6));
      await poolLogicProxy.deposit(USDC.address, units(20000, 6));
      // Deposit 2 WETH
      await WETH.approve(poolLogicProxy.address, units(2));
      await poolLogicProxy.deposit(WETH.address, units(2));
    });

    it("Should be able to deposit usdc and receive ausdc", async () => {
      // Pool balance: 20000 USDC, 2 WETH

      const amount = units(10000, 6);

      const depositABI = iLendingPool.encodeFunctionData("deposit", [USDC.address, amount, poolLogicProxy.address, 0]);

      // add supported assets
      await poolManagerLogicProxy
        .connect(manager)
        .changeAssets([{ asset: testParams.lendingPool, isDeposit: false }], []);

      // approve usdc
      const approveABI = iERC20.encodeFunctionData("approve", [testParams.lendingPool, amount]);
      await poolLogicProxy.connect(manager).execTransaction(USDC.address, approveABI);

      const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
      const aUsdcBalanceBefore = await aUSDC.balanceOf(poolLogicProxy.address);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      expect(usdcBalanceBefore).to.be.equal(20000e6);
      expect(aUsdcBalanceBefore).to.be.equal(0);

      // deposit
      await poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, depositABI);

      const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
      const aUsdcBalanceAfter = await aUSDC.balanceOf(poolLogicProxy.address);
      expect(usdcBalanceAfter).to.be.equal(10000e6);
      checkAlmostSame(aUsdcBalanceAfter, 10000e6, 0.001);
      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore, 0.001);
    });

    it("Should be able to deposit weth and receive aweth", async () => {
      // Pool balance: 10000 USDC, 2 WETH
      // Aave balance: 10000 aUSDC

      const amount = units(1);

      const depositABI = iLendingPool.encodeFunctionData("deposit", [WETH.address, amount, poolLogicProxy.address, 0]);

      // add supported assets
      await poolManagerLogicProxy
        .connect(manager)
        .changeAssets([{ asset: testParams.lendingPool, isDeposit: false }], []);

      // approve weth
      const approveABI = iERC20.encodeFunctionData("approve", [testParams.lendingPool, amount]);
      await poolLogicProxy.connect(manager).execTransaction(WETH.address, approveABI);

      const aWethBalanceBefore = await aWETH.balanceOf(poolLogicProxy.address);
      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      expect(aWethBalanceBefore).to.be.equal(0);

      // deposit
      await poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, depositABI);

      const wethBalanceAfter = await WETH.balanceOf(poolLogicProxy.address);
      const aWethBalanceAfter = await aWETH.balanceOf(poolLogicProxy.address);
      expect(wethBalanceAfter).to.be.equal(units(1));
      checkAlmostSame(aWethBalanceAfter, units(1), 0.001);
      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore, 0.001);
    });

    it("Should be able to borrow", async () => {
      // Pool balance: 10000 USDC, 1 WETH
      // Aave balance: 10000 aUSDC, 1 aWETH

      const amount = units(1);

      const borrowABI = iLendingPool.encodeFunctionData("borrow", [
        borrowAsset.address,
        amount,
        2,
        0,
        poolLogicProxy.address,
      ]);

      await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: borrowAsset.address, isDeposit: false }], []);

      const borrowAssetBalanceBefore = await borrowAsset.balanceOf(poolLogicProxy.address);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      expect(borrowAssetBalanceBefore).to.be.equal(0);

      // borrow
      await poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, borrowABI);

      const borrowAssetBalanceAfter = await borrowAsset.balanceOf(poolLogicProxy.address);
      expect(borrowAssetBalanceAfter).to.be.equal(amount);

      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore, 0.001);
    });

    it("should be able to withdraw", async () => {
      // Pool balance: 10000 USDC, 1 WETH, 1 borrowAsset
      // Aave balance: 10000 aUSDC, 1 aWETH, 1 debtBorrowAsset

      // Withdraw 40%
      const withdrawAmount = (await poolLogicProxy.totalSupply()).mul(40).div(100);

      const usdcBalanceBefore = await USDC.balanceOf(logicOwner.address);
      const wethBalanceBefore = await WETH.balanceOf(logicOwner.address);
      const borrowAssetBalanceBefore = await borrowAsset.balanceOf(logicOwner.address);
      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      await utils.increaseTime(86400);

      const complexAssetsData = await getComplexAssetsData(deployments, testParams, poolLogicProxy, withdrawAmount);
      await poolLogicProxy.withdrawSafe(withdrawAmount, complexAssetsData);

      const totalFundValueAfter = await poolManagerLogicProxy.totalFundValue();
      const expectedTotalFundValueAfter = totalFundValueBefore.mul(60).div(100);
      expect(totalFundValueAfter).to.be.gt(expectedTotalFundValueAfter);
      checkAlmostSame(totalFundValueAfter, expectedTotalFundValueAfter, 0.02);

      const usdcBalanceAfter = await USDC.balanceOf(logicOwner.address);
      const wethBalanceAfter = await WETH.balanceOf(logicOwner.address);
      const borrowAssetBalanceAfter = await borrowAsset.balanceOf(logicOwner.address);
      checkAlmostSame(usdcBalanceAfter, usdcBalanceBefore.add(units(4000, 6)), 0.001);
      checkAlmostSame(wethBalanceAfter, wethBalanceBefore.add(units(4, 17)), 0.001);
      const aavePositionWithdrawnValue = (
        await poolManagerLogicProxy["assetValue(address,uint256)"](USDC.address, units(10000, 6))
      )
        .add(await poolManagerLogicProxy["assetValue(address,uint256)"](WETH.address, units(1)))
        .sub(await poolManagerLogicProxy["assetValue(address,uint256)"](borrowAsset.address, units(1)))
        .mul(40)
        .div(100);
      const approxBorrowAssetTokensReceived = aavePositionWithdrawnValue
        .mul(units(1))
        .div(await poolManagerLogicProxy["assetValue(address,uint256)"](borrowAsset.address, units(1)));
      checkAlmostSame(
        borrowAssetBalanceAfter,
        borrowAssetBalanceBefore.add(units(4, 17)).add(approxBorrowAssetTokensReceived),
        0.1,
      );
    });

    it("Should be able to borrow more", async () => {
      const borrowAssetBalanceBefore = await borrowAsset.balanceOf(poolLogicProxy.address);

      const amount = units(1);

      const borrowABI = iLendingPool.encodeFunctionData("borrow", [
        borrowAsset.address,
        amount,
        2,
        0,
        poolLogicProxy.address,
      ]);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      // borrow
      await poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, borrowABI);

      const borrowAssetBalanceAfter = await borrowAsset.balanceOf(poolLogicProxy.address);

      expect(borrowAssetBalanceAfter).to.equal(borrowAssetBalanceBefore.add(amount));
      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore, 0.001);
    });

    it("Should be able to repay borrowAsset", async () => {
      // Simulate swaping 1000 usdc for 1 borrowAsset
      await getAccountToken(
        (await getBalance(poolLogicProxy.address, USDC.address)).sub(units(1000, 6)),
        poolLogicProxy.address,
        USDC.address,
        testParams.assetsBalanceOfSlot.usdc,
      );
      await getAccountToken(
        units(2),
        poolLogicProxy.address,
        borrowAsset.address,
        testParams.assetsBalanceOfSlot.borrowAsset,
      );
      // End simulation

      const debtBorrowAssetBalanceBefore = await debtBorrowAsset.balanceOf(poolLogicProxy.address);
      const borrowAssetBalanceBefore = await borrowAsset.balanceOf(poolLogicProxy.address);
      expect(debtBorrowAssetBalanceBefore).to.be.gt(0);
      expect(borrowAssetBalanceBefore).to.be.gt(debtBorrowAssetBalanceBefore);

      const amount = units(2); // max / full repayment
      const repayABI = iLendingPool.encodeFunctionData("repay", [
        borrowAsset.address,
        amount,
        2,
        poolLogicProxy.address,
      ]);

      const approveABI = iERC20.encodeFunctionData("approve", [testParams.lendingPool, amount]);
      await poolLogicProxy.connect(manager).execTransaction(borrowAsset.address, approveABI);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      // repay
      await poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, repayABI);

      const debtBorrowAssetBalanceAfter = await debtBorrowAsset.balanceOf(poolLogicProxy.address);
      expect(debtBorrowAssetBalanceAfter).to.be.equal(0);

      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore, 0.001);
    });

    it("Should be able to borrow WETH", async () => {
      const wethBalanceBefore = await WETH.balanceOf(poolLogicProxy.address);

      const amount = units(1, 16); // small amount of WETH to borrow

      const borrowABI = iLendingPool.encodeFunctionData("borrow", [WETH.address, amount, 2, 0, poolLogicProxy.address]);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      // borrow
      await poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, borrowABI);

      const wethBalanceAfter = await WETH.balanceOf(poolLogicProxy.address);
      expect(wethBalanceAfter).to.be.gt(wethBalanceBefore);

      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore, 0.001);
    });

    it("Should be able to repay WETH", async () => {
      const debtWethBalanceBefore = await debtWETH.balanceOf(poolLogicProxy.address);
      expect(debtWethBalanceBefore).to.be.gt(0);

      const amount = units(10000); // max / full repayment

      const repayABI = iLendingPool.encodeFunctionData("repay", [WETH.address, amount, 2, poolLogicProxy.address]);

      // approve weth
      const approveABI = iERC20.encodeFunctionData("approve", [testParams.lendingPool, amount]);
      await poolLogicProxy.connect(manager).execTransaction(WETH.address, approveABI);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      // repay
      await poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, repayABI);

      const debtWethBalanceAfter = await debtWETH.balanceOf(poolLogicProxy.address);
      expect(debtWethBalanceAfter).to.be.equal(0);

      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore, 0.001);
    });
  });
};
