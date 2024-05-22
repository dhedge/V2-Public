import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { IERC20, PoolFactory, PoolLogic, PoolManagerLogic } from "../../../../types";
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
import { deployAaveV3TestInfrastructure, IAaveV3TestParameters, iLendingPool } from "./deployAaveV3TestInfrastructure";

export const testAaveV3WithWETH = (testParams: IAaveV3TestParameters) => {
  describe("Aave V3 Test with WETH", () => {
    let deployments: IBackboneDeployments;
    let WETH: IERC20,
      USDC: IERC20,
      DAI: IERC20,
      AMUSDC: IERC20,
      AMWETH: IERC20,
      VariableDAI: IERC20,
      VariableWETH: IERC20;
    let logicOwner: SignerWithAddress, manager: SignerWithAddress;
    let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;

    utils.beforeAfterReset(before, after);

    before(async () => {
      deployments = await deployBackboneContracts(testParams);
      await deployAaveV3TestInfrastructure(deployments, testParams);

      poolFactory = deployments.poolFactory;
      logicOwner = deployments.owner;
      manager = deployments.manager;

      WETH = deployments.assets.WETH;
      USDC = deployments.assets.USDC;
      DAI = deployments.assets.DAI;
      AMUSDC = <IERC20>await ethers.getContractAt(IERC20Path, testParams.aTokens.usdc);
      AMWETH = <IERC20>await ethers.getContractAt(IERC20Path, testParams.aTokens.weth);
      VariableWETH = <IERC20>await ethers.getContractAt(IERC20Path, testParams.variableDebtTokens.weth);
      VariableDAI = <IERC20>await ethers.getContractAt(IERC20Path, testParams.variableDebtTokens.dai);

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
      // Deposit 20000 WETH
      await WETH.approve(poolLogicProxy.address, units(20000));
      await poolLogicProxy.deposit(WETH.address, units(20000));
    });

    it("Should be able to deposit usdc and receive amusdc", async () => {
      // Pool balance: 20000 USDC, 20000 WETH

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
      const amusdcBalanceBefore = await AMUSDC.balanceOf(poolLogicProxy.address);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      expect(usdcBalanceBefore).to.be.equal((20000e6).toString());
      expect(amusdcBalanceBefore).to.be.equal(0);

      // deposit
      await poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, depositABI);

      const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
      const amusdcBalanceAfter = await AMUSDC.balanceOf(poolLogicProxy.address);
      expect(usdcBalanceAfter).to.be.equal((10000e6).toString());
      checkAlmostSame(amusdcBalanceAfter, 10000e6);
      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
    });

    it("Should be able to deposit weth and receive amweth", async () => {
      // Pool balance: 10000 USDC, 20000 WETH
      // Aave balance: 10000 amUSDC

      const amount = units(10000);

      const depositABI = iLendingPool.encodeFunctionData("deposit", [WETH.address, amount, poolLogicProxy.address, 0]);

      // add supported assets
      await poolManagerLogicProxy
        .connect(manager)
        .changeAssets([{ asset: testParams.lendingPool, isDeposit: false }], []);

      // approve weth
      const approveABI = iERC20.encodeFunctionData("approve", [testParams.lendingPool, amount]);
      await poolLogicProxy.connect(manager).execTransaction(WETH.address, approveABI);

      const amwethBalanceBefore = await AMWETH.balanceOf(poolLogicProxy.address);
      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      expect(amwethBalanceBefore).to.be.equal(0);

      // deposit
      await poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, depositABI);

      const wethBalanceAfter = await WETH.balanceOf(poolLogicProxy.address);
      const amwethBalanceAfter = await AMWETH.balanceOf(poolLogicProxy.address);
      checkAlmostSame(wethBalanceAfter, amount);
      checkAlmostSame(amwethBalanceAfter, amount);
      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
    });

    it("Should be able to borrow DAI", async () => {
      // Pool balance: 10000 USDC, 10000 WETH
      // Aave balance: 10000 amUSDC, 10000 amWETH

      const amount = (5000e6).toString();

      const borrowABI = iLendingPool.encodeFunctionData("borrow", [DAI.address, amount, 2, 0, poolLogicProxy.address]);

      await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: DAI.address, isDeposit: false }], []);

      const daiBalanceBefore = await DAI.balanceOf(poolLogicProxy.address);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      expect(daiBalanceBefore).to.be.equal(0);

      // borrow
      await poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, borrowABI);

      const daiBalanceAfter = await DAI.balanceOf(poolLogicProxy.address);
      expect(daiBalanceAfter).to.be.equal(amount);

      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
    });

    it("should be able to withdraw", async () => {
      // Pool balance: 10000 USDC, 10000 WETH, 5000 DAI
      // Aave balance: 10000 amUSDC, 10000 amWETH, 5000 debtDAI

      // enable weth to check withdraw process
      await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: WETH.address, isDeposit: false }], []);

      // Withdraw 40%
      const withdrawAmount = (await poolLogicProxy.totalSupply()).mul(40).div(100);

      const usdcBalanceBefore = ethers.BigNumber.from(await USDC.balanceOf(logicOwner.address));
      const daiBalanceBefore = ethers.BigNumber.from(await DAI.balanceOf(logicOwner.address));
      const totalFundValueBefore = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());

      await ethers.provider.send("evm_increaseTime", [86400]);
      await poolLogicProxy.withdraw(withdrawAmount);

      const totalFundValueAfter = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());

      checkAlmostSame(totalFundValueAfter, totalFundValueBefore.mul(60).div(100));
      const usdcBalanceAfter = ethers.BigNumber.from(await USDC.balanceOf(logicOwner.address));
      const daiBalanceAfter = ethers.BigNumber.from(await DAI.balanceOf(logicOwner.address));
      checkAlmostSame(usdcBalanceAfter, usdcBalanceBefore.add((4000e6).toString()));
      checkAlmostSame(daiBalanceAfter, daiBalanceBefore.add((2000e6).toString()));
    });

    it("Should be able to borrow more DAI", async () => {
      const daiBalanceBefore = await DAI.balanceOf(poolLogicProxy.address);

      const amount = (1000e6).toString();

      const borrowABI = iLendingPool.encodeFunctionData("borrow", [DAI.address, amount, 2, 0, poolLogicProxy.address]);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      // borrow
      await poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, borrowABI);

      const daiBalanceAfter = await DAI.balanceOf(poolLogicProxy.address);

      checkAlmostSame(daiBalanceAfter, daiBalanceBefore.add(amount));
      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
    });

    it("Should be able to repay DAI", async () => {
      // Simulate swaping 1000usdc for 1000 dai
      await getAccountToken(
        (await getBalance(poolLogicProxy.address, USDC.address)).sub(units(1000, 6)),
        poolLogicProxy.address,
        USDC.address,
        testParams.assetsBalanceOfSlot.usdc,
      );
      await getAccountToken(units(1000), poolLogicProxy.address, DAI.address, testParams.assetsBalanceOfSlot.dai);
      // End sim

      const debtDaiBefore = await VariableDAI.balanceOf(poolLogicProxy.address);
      const daiBalanceBefore = await DAI.balanceOf(poolLogicProxy.address);
      expect(debtDaiBefore).to.be.gt(0);
      expect(daiBalanceBefore).to.be.gt(debtDaiBefore);

      const amount = units(10000); // max / full repayment
      const repayABI = iLendingPool.encodeFunctionData("repay", [DAI.address, amount, 2, poolLogicProxy.address]);

      // approve dai
      const approveABI = iERC20.encodeFunctionData("approve", [testParams.lendingPool, amount]);
      await poolLogicProxy.connect(manager).execTransaction(DAI.address, approveABI);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      // repay
      await poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, repayABI);

      const debtDaiAfter = await VariableDAI.balanceOf(poolLogicProxy.address);
      expect(debtDaiAfter).to.be.equal(0);

      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
    });

    it("Should be able to borrow WETH", async () => {
      const wethBalanceBefore = await WETH.balanceOf(poolLogicProxy.address);

      const amount = (1e16).toString(); // small amount of WETH to borrow

      const borrowABI = iLendingPool.encodeFunctionData("borrow", [WETH.address, amount, 2, 0, poolLogicProxy.address]);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      // borrow
      await poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, borrowABI);

      const wethBalanceAfter = await WETH.balanceOf(poolLogicProxy.address);
      expect(wethBalanceAfter).to.be.gt(wethBalanceBefore);

      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
    });

    it("Should be able to repay WETH", async () => {
      const debtWethBefore = await VariableWETH.balanceOf(poolLogicProxy.address);
      expect(debtWethBefore).to.be.gt(0);

      const amount = units(10000); // max / full repayment

      const repayABI = iLendingPool.encodeFunctionData("repay", [WETH.address, amount, 2, poolLogicProxy.address]);

      // approve weth
      const approveABI = iERC20.encodeFunctionData("approve", [testParams.lendingPool, amount]);
      await poolLogicProxy.connect(manager).execTransaction(WETH.address, approveABI);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      // repay
      await poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, repayABI);

      const debtWethAfter = await VariableWETH.balanceOf(poolLogicProxy.address);
      expect(debtWethAfter).to.be.equal(0);

      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
    });
  });
};
