import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect, use } from "chai";
import { solidity } from "ethereum-waffle";
import { ethers } from "hardhat";
import { polygonChainData } from "../../../config/chainData/polygon-data";
import {
  IERC20,
  IERC20__factory,
  ILendingPool__factory,
  IUniswapV2Router__factory,
  PoolFactory,
  PoolLogic,
  PoolManagerLogic,
} from "../../../types";
import { checkAlmostSame, getAmountOut, units } from "../../TestHelpers";
import { createFund } from "../utils/createFund";
import { deployContracts } from "../utils/deployContracts/deployContracts";
import { getAccountToken } from "../utils/getAccountTokens";
import { utils } from "../utils/utils";
const { sushi, aaveV2, assets, assetsBalanceOfSlot } = polygonChainData;

use(solidity);

describe("Aave Edge Test", function () {
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
  const iSushiswapV2Router = new ethers.utils.Interface(IUniswapV2Router__factory.abi);

  let snapId: string;

  after(async () => {
    await utils.evmRestoreSnap(snapId);
  });

  before(async function () {
    [logicOwner, manager] = await ethers.getSigners();
    snapId = await utils.evmTakeSnap();
    await ethers.provider.send("evm_mine", []);
    const deployments = await deployContracts("polygon");
    poolFactory = deployments.poolFactory;
    WETH = deployments.assets.WETH;
    USDC = deployments.assets.USDC;
    DAI = deployments.assets.DAI;
    // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
    AMUSDC = deployments.assets.AMUSDC!;
    // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
    AMWETH = deployments.assets.AMWETH!;
    // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
    VariableWETH = deployments.assets.VariableWETH!;
    // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
    VariableDAI = deployments.assets.VariableDAI!;

    await getAccountToken(units(10000, 6), logicOwner.address, assets.usdc, assetsBalanceOfSlot.usdc);
    await getAccountToken(units(10000), logicOwner.address, assets.weth, assetsBalanceOfSlot.weth);

    const funds = await createFund(poolFactory, logicOwner, manager, [
      { asset: assets.usdc, isDeposit: true },
      { asset: assets.weth, isDeposit: true },
    ]);
    poolLogicProxy = funds.poolLogicProxy;
    poolManagerLogicProxy = funds.poolManagerLogicProxy;

    // Deposit 200 USDC
    await USDC.approve(poolLogicProxy.address, units(200, 6));
    await poolLogicProxy.deposit(assets.usdc, units(200, 6));
    // Deposit 200 WETh
    await WETH.approve(poolLogicProxy.address, units(200));
    await poolLogicProxy.deposit(assets.weth, units(200));
  });

  it("Should be able to deposit usdc and receive amusdc", async () => {
    // Pool balance: 200 USDC, 200 WETH

    const amount = units(100, 6);

    const depositABI = iLendingPool.encodeFunctionData("deposit", [assets.usdc, amount, poolLogicProxy.address, 0]);

    // add supported assets
    await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: aaveV2.lendingPool, isDeposit: false }], []);

    // approve usdc
    const approveABI = iERC20.encodeFunctionData("approve", [aaveV2.lendingPool, amount]);
    await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);

    const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
    const amusdcBalanceBefore = await AMUSDC.balanceOf(poolLogicProxy.address);

    const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

    expect(usdcBalanceBefore).to.be.equal((200e6).toString());
    expect(amusdcBalanceBefore).to.be.equal(0);

    // deposit
    await poolLogicProxy.connect(manager).execTransaction(aaveV2.lendingPool, depositABI);

    const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
    const amusdcBalanceAfter = await AMUSDC.balanceOf(poolLogicProxy.address);
    expect(usdcBalanceAfter).to.be.equal((100e6).toString());
    checkAlmostSame(amusdcBalanceAfter, 100e6);
    checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
  });

  it("Should be able to deposit weth and receive amweth", async () => {
    // Pool balance: 100 USDC, 200 WETH
    // Aave balance: 100 amUSDC

    const amount = units(100);

    const depositABI = iLendingPool.encodeFunctionData("deposit", [assets.weth, amount, poolLogicProxy.address, 0]);

    // add supported assets
    await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: aaveV2.lendingPool, isDeposit: false }], []);

    // approve weth
    const approveABI = iERC20.encodeFunctionData("approve", [aaveV2.lendingPool, amount]);
    await poolLogicProxy.connect(manager).execTransaction(assets.weth, approveABI);

    const amwethBalanceBefore = await AMWETH.balanceOf(poolLogicProxy.address);
    const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

    expect(amwethBalanceBefore).to.be.equal(0);

    // deposit
    await poolLogicProxy.connect(manager).execTransaction(aaveV2.lendingPool, depositABI);

    const wethBalanceAfter = await WETH.balanceOf(poolLogicProxy.address);
    const amwethBalanceAfter = await AMWETH.balanceOf(poolLogicProxy.address);
    checkAlmostSame(wethBalanceAfter, amount);
    checkAlmostSame(amwethBalanceAfter, amount);
    checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
  });

  it("Should be able to borrow DAI", async () => {
    // Pool balance: 100 USDC, 100 WETH
    // Aave balance: 100 amUSDC, 100 amWETH

    const amount = (50e6).toString();

    const borrowABI = iLendingPool.encodeFunctionData("borrow", [assets.dai, amount, 2, 0, poolLogicProxy.address]);

    await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: assets.dai, isDeposit: false }], []);

    const daiBalanceBefore = await DAI.balanceOf(poolLogicProxy.address);

    const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

    expect(daiBalanceBefore).to.be.equal(0);

    // borrow
    await poolLogicProxy.connect(manager).execTransaction(aaveV2.lendingPool, borrowABI);

    const daiBalanceAfter = await DAI.balanceOf(poolLogicProxy.address);
    expect(daiBalanceAfter).to.be.equal(amount);

    checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
  });

  it("should be able to withdraw", async function () {
    // Pool balance: 100 USDC, 100 WETH, 50 DAI
    // Aave balance: 100 amUSDC, 100 amWETH, 50 debtDAI

    // enable weth to check withdraw process
    await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: assets.weth, isDeposit: false }], []);

    // Withdraw 40%
    const withdrawAmount = (await poolLogicProxy.totalSupply()).mul(40).div(100);

    const usdcBalanceBefore = ethers.BigNumber.from(await USDC.balanceOf(logicOwner.address));
    const daiBalanceBefore = ethers.BigNumber.from(await DAI.balanceOf(logicOwner.address));
    const totalFundValueBefore = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());

    // Unapprove WETH in Sushiswap to test conditional approval logic
    const approveABI = iERC20.encodeFunctionData("approve", [sushi.router, (0).toString()]);
    await poolLogicProxy.connect(manager).execTransaction(assets.weth, approveABI);

    await ethers.provider.send("evm_increaseTime", [86400]);
    await poolLogicProxy.withdraw(withdrawAmount);

    const totalFundValueAfter = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());

    checkAlmostSame(totalFundValueAfter, totalFundValueBefore.mul(60).div(100));
    const usdcBalanceAfter = ethers.BigNumber.from(await USDC.balanceOf(logicOwner.address));
    const daiBalanceAfter = ethers.BigNumber.from(await DAI.balanceOf(logicOwner.address));
    checkAlmostSame(usdcBalanceAfter, usdcBalanceBefore.add((20e6).toString()));
    checkAlmostSame(daiBalanceAfter, daiBalanceBefore.add((20e6).toString()));
  });

  it("Should be able to borrow more DAI", async () => {
    const daiBalanceBefore = await DAI.balanceOf(poolLogicProxy.address);

    const amount = (10e6).toString();

    const borrowABI = iLendingPool.encodeFunctionData("borrow", [assets.dai, amount, 2, 0, poolLogicProxy.address]);

    const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

    // borrow
    await poolLogicProxy.connect(manager).execTransaction(aaveV2.lendingPool, borrowABI);

    const daiBalanceAfter = await DAI.balanceOf(poolLogicProxy.address);

    checkAlmostSame(daiBalanceAfter, daiBalanceBefore.add(amount));
    checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
  });

  it("Should be able to repay DAI", async () => {
    // Swap some USDC for more DAI first to be able to pay back the loan
    const sourceAmount = (10e6).toString();

    // First approve USDC
    let approveABI = iERC20.encodeFunctionData("approve", [sushi.router, sourceAmount]);
    await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);

    const swapABI = iSushiswapV2Router.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      await getAmountOut(sushi.router, sourceAmount, [assets.usdc, assets.dai]),
      [assets.usdc, assets.dai],
      poolLogicProxy.address,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);
    await poolLogicProxy.connect(manager).execTransaction(sushi.router, swapABI);

    const debtDaiBefore = await VariableDAI.balanceOf(poolLogicProxy.address);
    const daiBalanceBefore = await DAI.balanceOf(poolLogicProxy.address);
    expect(debtDaiBefore).to.be.gt(0);
    expect(daiBalanceBefore).to.be.gt(debtDaiBefore);

    const amount = units(10000); // max / full repayment
    const repayABI = iLendingPool.encodeFunctionData("repay", [assets.dai, amount, 2, poolLogicProxy.address]);

    // approve dai
    approveABI = iERC20.encodeFunctionData("approve", [aaveV2.lendingPool, amount]);
    await poolLogicProxy.connect(manager).execTransaction(assets.dai, approveABI);

    const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

    // repay
    await poolLogicProxy.connect(manager).execTransaction(aaveV2.lendingPool, repayABI);

    const debtDaiAfter = await VariableDAI.balanceOf(poolLogicProxy.address);
    expect(debtDaiAfter).to.be.equal(0);

    checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
  });

  it("Should be able to borrow WETH", async () => {
    const wethBalanceBefore = await WETH.balanceOf(poolLogicProxy.address);

    const amount = (1e14).toString(); // small amount of WETH to borrow

    const borrowABI = iLendingPool.encodeFunctionData("borrow", [assets.weth, amount, 2, 0, poolLogicProxy.address]);

    const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

    // borrow
    await poolLogicProxy.connect(manager).execTransaction(aaveV2.lendingPool, borrowABI);

    const wethBalanceAfter = await WETH.balanceOf(poolLogicProxy.address);
    expect(wethBalanceAfter).to.be.gt(wethBalanceBefore);

    checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
  });

  it("Should be able to repay WETH", async () => {
    const debtWethBefore = await VariableWETH.balanceOf(poolLogicProxy.address);
    expect(debtWethBefore).to.be.gt(0);

    const amount = units(10000); // max / full repayment

    const repayABI = iLendingPool.encodeFunctionData("repay", [assets.weth, amount, 2, poolLogicProxy.address]);

    // approve weth
    const approveABI = iERC20.encodeFunctionData("approve", [aaveV2.lendingPool, amount]);
    await poolLogicProxy.connect(manager).execTransaction(assets.weth, approveABI);

    const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

    // repay
    await poolLogicProxy.connect(manager).execTransaction(aaveV2.lendingPool, repayABI);

    const debtWethAfter = await VariableWETH.balanceOf(poolLogicProxy.address);
    expect(debtWethAfter).to.be.equal(0);

    checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
  });
});
