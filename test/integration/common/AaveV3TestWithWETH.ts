import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import {
  IERC20,
  IERC20__factory,
  ILendingPool__factory,
  PoolFactory,
  PoolLogic,
  PoolManagerLogic,
} from "../../../types";
import { checkAlmostSame, units } from "../../TestHelpers";
import { createFund } from "../utils/createFund";
import { deployContracts, NETWORK } from "../utils/deployContracts/deployContracts";
import { getAccountToken } from "../utils/getAccountTokens";
import { getBalance } from "../utils/getAccountTokens/index";
import { utils } from "../utils/utils";

interface IAaveV3TestParameters {
  network: NETWORK;
  aaveLendingPool: string;
  swapRouter: string;
  weth: {
    address: string;
    slotOfBalance: number;
    aToken: string;
    variableDebtToken: string;
  };
  usdc: {
    address: string;
    slotOfBalance: number;
    aToken: string;
  };
  dai: {
    address: string;
    aToken: string;
    variableDebtToken: string;
    slotOfBalance: number;
  };
}

export const testAaveV3WithWETH = ({
  network,
  aaveLendingPool,
  swapRouter,
  weth,
  usdc,
  dai,
}: IAaveV3TestParameters) => {
  describe("Aave V3 Test with WETH", function () {
    let WETH: IERC20,
      USDC: IERC20,
      DAI: IERC20,
      AMUSDC: IERC20,
      AMWETH: IERC20,
      VariableDAI: IERC20,
      VariableWETH: IERC20;
    let logicOwner: SignerWithAddress, manager: SignerWithAddress;
    let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
    const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);
    const iLendingPool = new ethers.utils.Interface(ILendingPool__factory.abi);

    utils.beforeAfterReset(before, after);

    before(async function () {
      [logicOwner, manager] = await ethers.getSigners();
      const deployments = await deployContracts(network);
      poolFactory = deployments.poolFactory;

      WETH = <IERC20>await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", weth.address);
      USDC = <IERC20>await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", usdc.address);
      DAI = <IERC20>await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", dai.address);
      AMUSDC = <IERC20>await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", usdc.aToken);
      AMWETH = <IERC20>await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", weth.aToken);
      VariableWETH = <IERC20>(
        await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", weth.variableDebtToken)
      );
      VariableDAI = <IERC20>(
        await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", dai.variableDebtToken)
      );

      await getAccountToken(units(100000, 6), logicOwner.address, usdc.address, usdc.slotOfBalance);
      await getAccountToken(units(100000), logicOwner.address, weth.address, weth.slotOfBalance);

      const funds = await createFund(poolFactory, logicOwner, manager, [
        { asset: usdc.address, isDeposit: true },
        { asset: weth.address, isDeposit: true },
      ]);
      poolLogicProxy = funds.poolLogicProxy;
      poolManagerLogicProxy = funds.poolManagerLogicProxy;

      // Deposit 20000 USDC
      await USDC.approve(poolLogicProxy.address, units(20000, 6));
      await poolLogicProxy.deposit(usdc.address, units(20000, 6));
      // Deposit 20000 WETh
      await WETH.approve(poolLogicProxy.address, units(20000));
      await poolLogicProxy.deposit(weth.address, units(20000));

      // set slipage to 10%
      await deployments.uniswapV3RouterGuard.setSlippageLimit(10, 100);
      await deployments.uniswapV2RouterGuard.setSlippageLimit(10, 100);
    });

    it("Should be able to deposit usdc and receive amusdc", async () => {
      // Pool balance: 20000 USDC, 20000 WETH

      const amount = units(10000, 6);

      const depositABI = iLendingPool.encodeFunctionData("deposit", [usdc.address, amount, poolLogicProxy.address, 0]);

      // add supported assets
      await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: aaveLendingPool, isDeposit: false }], []);

      // approve usdc
      const approveABI = iERC20.encodeFunctionData("approve", [aaveLendingPool, amount]);
      await poolLogicProxy.connect(manager).execTransaction(usdc.address, approveABI);

      const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
      const amusdcBalanceBefore = await AMUSDC.balanceOf(poolLogicProxy.address);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      expect(usdcBalanceBefore).to.be.equal((20000e6).toString());
      expect(amusdcBalanceBefore).to.be.equal(0);

      // deposit
      await poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, depositABI);

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

      const depositABI = iLendingPool.encodeFunctionData("deposit", [weth.address, amount, poolLogicProxy.address, 0]);

      // add supported assets
      await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: aaveLendingPool, isDeposit: false }], []);

      // approve weth
      const approveABI = iERC20.encodeFunctionData("approve", [aaveLendingPool, amount]);
      await poolLogicProxy.connect(manager).execTransaction(weth.address, approveABI);

      const amwethBalanceBefore = await AMWETH.balanceOf(poolLogicProxy.address);
      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      expect(amwethBalanceBefore).to.be.equal(0);

      // deposit
      await poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, depositABI);

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

      const borrowABI = iLendingPool.encodeFunctionData("borrow", [dai.address, amount, 2, 0, poolLogicProxy.address]);

      await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: dai.address, isDeposit: false }], []);

      const daiBalanceBefore = await DAI.balanceOf(poolLogicProxy.address);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      expect(daiBalanceBefore).to.be.equal(0);

      // borrow
      await poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, borrowABI);

      const daiBalanceAfter = await DAI.balanceOf(poolLogicProxy.address);
      expect(daiBalanceAfter).to.be.equal(amount);

      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
    });

    it("should be able to withdraw", async function () {
      // Pool balance: 10000 USDC, 10000 WETH, 5000 DAI
      // Aave balance: 10000 amUSDC, 10000 amWETH, 5000 debtDAI

      // enable weth to check withdraw process
      await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: weth.address, isDeposit: false }], []);

      // Withdraw 40%
      const withdrawAmount = (await poolLogicProxy.totalSupply()).mul(40).div(100);

      const usdcBalanceBefore = ethers.BigNumber.from(await USDC.balanceOf(logicOwner.address));
      const daiBalanceBefore = ethers.BigNumber.from(await DAI.balanceOf(logicOwner.address));
      const totalFundValueBefore = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());

      // Unapprove WETH in Sushiswap to test conditional approval logic
      const approveABI = iERC20.encodeFunctionData("approve", [swapRouter, (0).toString()]);
      await poolLogicProxy.connect(manager).execTransaction(weth.address, approveABI);

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

      const borrowABI = iLendingPool.encodeFunctionData("borrow", [dai.address, amount, 2, 0, poolLogicProxy.address]);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      // borrow
      await poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, borrowABI);

      const daiBalanceAfter = await DAI.balanceOf(poolLogicProxy.address);

      checkAlmostSame(daiBalanceAfter, daiBalanceBefore.add(amount));
      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
    });

    it("Should be able to repay DAI", async () => {
      // Simulate swaping 1000usdc for 1000 dai
      await getAccountToken(
        (await getBalance(poolLogicProxy.address, usdc.address)).sub(units(1000, 6)),
        poolLogicProxy.address,
        usdc.address,
        usdc.slotOfBalance,
      );
      await getAccountToken(units(1000), poolLogicProxy.address, dai.address, dai.slotOfBalance);
      // End sim

      const debtDaiBefore = await VariableDAI.balanceOf(poolLogicProxy.address);
      const daiBalanceBefore = await DAI.balanceOf(poolLogicProxy.address);
      expect(debtDaiBefore).to.be.gt(0);
      expect(daiBalanceBefore).to.be.gt(debtDaiBefore);

      const amount = units(10000); // max / full repayment
      const repayABI = iLendingPool.encodeFunctionData("repay", [dai.address, amount, 2, poolLogicProxy.address]);

      // approve dai
      const approveABI = iERC20.encodeFunctionData("approve", [aaveLendingPool, amount]);
      await poolLogicProxy.connect(manager).execTransaction(dai.address, approveABI);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      // repay
      await poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, repayABI);

      const debtDaiAfter = await VariableDAI.balanceOf(poolLogicProxy.address);
      expect(debtDaiAfter).to.be.equal(0);

      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
    });

    it("Should be able to borrow WETH", async () => {
      const wethBalanceBefore = await WETH.balanceOf(poolLogicProxy.address);

      const amount = (1e16).toString(); // small amount of WETH to borrow

      const borrowABI = iLendingPool.encodeFunctionData("borrow", [weth.address, amount, 2, 0, poolLogicProxy.address]);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      // borrow
      await poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, borrowABI);

      const wethBalanceAfter = await WETH.balanceOf(poolLogicProxy.address);
      expect(wethBalanceAfter).to.be.gt(wethBalanceBefore);

      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
    });

    it("Should be able to repay WETH", async () => {
      const debtWethBefore = await VariableWETH.balanceOf(poolLogicProxy.address);
      expect(debtWethBefore).to.be.gt(0);

      const amount = units(10000); // max / full repayment

      const repayABI = iLendingPool.encodeFunctionData("repay", [weth.address, amount, 2, poolLogicProxy.address]);

      // approve weth
      const approveABI = iERC20.encodeFunctionData("approve", [aaveLendingPool, amount]);
      await poolLogicProxy.connect(manager).execTransaction(weth.address, approveABI);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      // repay
      await poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, repayABI);

      const debtWethAfter = await VariableWETH.balanceOf(poolLogicProxy.address);
      expect(debtWethAfter).to.be.equal(0);

      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
    });
  });
};
