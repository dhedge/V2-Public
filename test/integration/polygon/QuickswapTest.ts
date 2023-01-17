import { ethers } from "hardhat";
import { solidity } from "ethereum-waffle";
import { expect, use } from "chai";
import { checkAlmostSame, getAmountIn, getAmountOut, units } from "../../TestHelpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import {
  IERC20,
  IERC20__factory,
  IStakingRewards__factory,
  IUniswapV2Router__factory,
  IWETH,
  PoolFactory,
  PoolLogic,
  PoolManagerLogic,
} from "../../../types";
import { createFund } from "../utils/createFund";

import { getAccountToken } from "../utils/getAccountTokens";
import { deployContracts } from "../utils/deployContracts/deployContracts";

import { polygonChainData } from "../../../config/chainData/polygon-data";
const { assets, assetsBalanceOfSlot, quickswap } = polygonChainData;

use(solidity);

describe("Quickswap V2 Test", function () {
  let WMATIC: IWETH, WETH: IERC20, USDC: IERC20, QuickLPUSDCWETH: IERC20, QUICK: IERC20;
  let logicOwner: SignerWithAddress, manager: SignerWithAddress, user: SignerWithAddress;
  let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
  const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);
  const iQuickswapRouter = new ethers.utils.Interface(IUniswapV2Router__factory.abi);
  const iUniswapV2Router = new ethers.utils.Interface(IUniswapV2Router__factory.abi);
  const iStakingRewards = new ethers.utils.Interface(IStakingRewards__factory.abi);

  before(async function () {
    [logicOwner, manager, user] = await ethers.getSigners();
    const deployments = await deployContracts("polygon");
    poolFactory = deployments.poolFactory;
    USDC = deployments.assets.USDC;
    WETH = deployments.assets.WETH;
    // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
    QuickLPUSDCWETH = deployments.assets.QuickLPUSDCWETH!;
    // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
    QUICK = deployments.assets.QUICK!;

    await deployments.assetHandler.removeAsset(assets.wmatic);

    WMATIC = await ethers.getContractAt("IWETH", assets.wmatic);

    await getAccountToken(units(10000, 6), logicOwner.address, assets.usdc, assetsBalanceOfSlot.usdc);
    await getAccountToken(units(10000), logicOwner.address, assets.weth, assetsBalanceOfSlot.weth);

    const funds = await createFund(poolFactory, logicOwner, manager, [
      { asset: assets.usdc, isDeposit: true },
      { asset: assets.usdt, isDeposit: true },
    ]);
    poolLogicProxy = funds.poolLogicProxy;
    poolManagerLogicProxy = funds.poolManagerLogicProxy;
    // Deposit 200 USDC
    await USDC.approve(poolLogicProxy.address, units(200, 6));
    await poolLogicProxy.deposit(assets.usdc, units(200, 6));
  });

  it("Should be able to approve", async () => {
    let approveABI = iERC20.encodeFunctionData("approve", [assets.usdc, (200e6).toString()]);
    await expect(poolLogicProxy.connect(manager).execTransaction(assets.weth, approveABI)).to.be.revertedWith(
      "asset not enabled in pool",
    );

    await expect(poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI)).to.be.revertedWith(
      "unsupported spender approval",
    );

    approveABI = iERC20.encodeFunctionData("approve", [quickswap.router, (200e6).toString()]);
    await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);
  });

  it("should be able to swap tokens on quickswap(swapTokensForExactTokens).", async () => {
    const dstAmount = (100e6).toString();
    let swapABI = iQuickswapRouter.encodeFunctionData("swapTokensForExactTokens", [
      dstAmount,
      0,
      [assets.usdc, assets.usdt],
      poolManagerLogicProxy.address,
      0,
    ]);

    await expect(
      poolLogicProxy.connect(manager).execTransaction("0x0000000000000000000000000000000000000000", swapABI),
    ).to.be.revertedWith("non-zero address is required");

    swapABI = iQuickswapRouter.encodeFunctionData("swapTokensForExactTokens", [
      dstAmount,
      0,
      [assets.usdc, assets.usdt],
      poolLogicProxy.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(assets.usdc, swapABI)).to.be.revertedWith(
      "invalid transaction",
    );

    swapABI = iQuickswapRouter.encodeFunctionData("swapTokensForExactTokens", [
      dstAmount,
      0,
      [assets.usdc, assets.weth, assets.wmatic],
      poolLogicProxy.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(quickswap.router, swapABI)).to.be.revertedWith(
      "unsupported destination asset",
    );

    swapABI = iQuickswapRouter.encodeFunctionData("swapTokensForExactTokens", [
      dstAmount,
      0,
      [assets.usdc, assets.usdt],
      user.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(quickswap.router, swapABI)).to.be.revertedWith(
      "recipient is not pool",
    );

    swapABI = iQuickswapRouter.encodeFunctionData("swapTokensForExactTokens", [
      dstAmount,
      await getAmountIn(quickswap.router, dstAmount, [assets.usdc, assets.usdt]),
      [assets.usdc, assets.usdt],
      poolLogicProxy.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(quickswap.router, swapABI)).to.be.revertedWith(
      "UniswapV2Router: EXPIRED",
    );

    swapABI = iQuickswapRouter.encodeFunctionData("swapTokensForExactTokens", [
      dstAmount,
      await getAmountIn(quickswap.router, dstAmount, [assets.usdc, assets.usdt]),
      [assets.usdc, assets.usdt],
      poolLogicProxy.address,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);
    await poolLogicProxy.connect(manager).execTransaction(quickswap.router, swapABI);

    checkAlmostSame(await USDC.balanceOf(poolLogicProxy.address), dstAmount);
  });

  it("should be able to swap tokens on quickswap(swapExactTokensForTokens).", async () => {
    await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: assets.weth, isDeposit: false }], []);

    const sourceAmount = ethers.BigNumber.from(await USDC.balanceOf(poolLogicProxy.address)).div(2);
    let swapABI = iQuickswapRouter.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      0,
      [assets.usdc, assets.weth],
      poolManagerLogicProxy.address,
      0,
    ]);

    await expect(
      poolLogicProxy.connect(manager).execTransaction("0x0000000000000000000000000000000000000000", swapABI),
    ).to.be.revertedWith("non-zero address is required");

    swapABI = iQuickswapRouter.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      0,
      [assets.wmatic, assets.weth],
      poolLogicProxy.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(assets.usdc, swapABI)).to.be.revertedWith(
      "invalid transaction",
    );

    swapABI = iQuickswapRouter.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      0,
      [assets.usdc, assets.weth, assets.wmatic],
      poolLogicProxy.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(quickswap.router, swapABI)).to.be.revertedWith(
      "unsupported destination asset",
    );

    swapABI = iQuickswapRouter.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      0,
      [assets.usdc, assets.weth],
      user.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(quickswap.router, swapABI)).to.be.revertedWith(
      "recipient is not pool",
    );

    swapABI = iQuickswapRouter.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      await getAmountOut(quickswap.router, sourceAmount, [assets.usdc, assets.weth]),
      [assets.usdc, assets.weth],
      poolLogicProxy.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(quickswap.router, swapABI)).to.be.revertedWith(
      "UniswapV2Router: EXPIRED",
    );

    swapABI = iQuickswapRouter.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      await getAmountOut(quickswap.router, sourceAmount, [assets.usdc, assets.weth]),
      [assets.usdc, assets.weth],
      poolLogicProxy.address,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);
    await poolLogicProxy.connect(manager).execTransaction(quickswap.router, swapABI);

    checkAlmostSame(await USDC.balanceOf(poolLogicProxy.address), sourceAmount);
  });

  it("should be able to withdraw", async function () {
    // Withdraw 50%
    const withdrawAmount = units(100);

    await ethers.provider.send("evm_increaseTime", [86400]);

    await poolLogicProxy.withdraw(withdrawAmount);
  });

  it("manager can add liquidity", async () => {
    await poolManagerLogicProxy
      .connect(manager)
      .changeAssets([{ asset: quickswap.pools.usdc_weth.address, isDeposit: false }], []);

    const tokenA = assets.usdc;
    const tokenB = assets.weth;
    const amountADesired = await USDC.balanceOf(poolLogicProxy.address);
    const amountBDesired = await WETH.balanceOf(poolLogicProxy.address);
    const addLiquidityAbi = iUniswapV2Router.encodeFunctionData("addLiquidity", [
      tokenA,
      tokenB,
      amountADesired,
      amountBDesired,
      0,
      0,
      poolLogicProxy.address,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);

    let approveABI = iERC20.encodeFunctionData("approve", [quickswap.router, amountADesired]);
    await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);
    approveABI = iERC20.encodeFunctionData("approve", [quickswap.router, amountBDesired]);
    await poolLogicProxy.connect(manager).execTransaction(assets.weth, approveABI);

    const lpBalanceBefore = await QuickLPUSDCWETH.balanceOf(poolLogicProxy.address);
    const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
    const wethBalanceBefore = await WETH.balanceOf(poolLogicProxy.address);
    const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

    expect(lpBalanceBefore).to.be.equal(0);

    await poolLogicProxy.connect(manager).execTransaction(quickswap.router, addLiquidityAbi);

    expect(await QuickLPUSDCWETH.balanceOf(poolLogicProxy.address)).to.be.gt(lpBalanceBefore);
    expect(await USDC.balanceOf(poolLogicProxy.address)).to.be.lt(usdcBalanceBefore);
    expect(await WETH.balanceOf(poolLogicProxy.address)).to.be.lt(wethBalanceBefore);
    checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
  });

  it("should be able to remove liquidity on quickswap.", async () => {
    const tokenA = assets.usdc;
    const tokenB = assets.weth;
    const liquidity = ethers.BigNumber.from(await QuickLPUSDCWETH.balanceOf(poolLogicProxy.address)).div(2);

    let removeLiquidityAbi = iUniswapV2Router.encodeFunctionData("removeLiquidity", [
      assets.wmatic,
      tokenB,
      liquidity,
      0,
      0,
      poolLogicProxy.address,
      0,
    ]);
    await expect(
      poolLogicProxy.connect(manager).execTransaction(quickswap.router, removeLiquidityAbi),
    ).to.be.revertedWith("unsupported asset: tokenA");

    removeLiquidityAbi = iUniswapV2Router.encodeFunctionData("removeLiquidity", [
      tokenA,
      assets.wmatic,
      liquidity,
      0,
      0,
      poolLogicProxy.address,
      0,
    ]);
    await expect(
      poolLogicProxy.connect(manager).execTransaction(quickswap.router, removeLiquidityAbi),
    ).to.be.revertedWith("unsupported asset: tokenB");

    removeLiquidityAbi = iUniswapV2Router.encodeFunctionData("removeLiquidity", [
      tokenA,
      tokenB,
      liquidity,
      0,
      0,
      user.address,
      0,
    ]);
    await expect(
      poolLogicProxy.connect(manager).execTransaction(quickswap.router, removeLiquidityAbi),
    ).to.be.revertedWith("recipient is not pool");

    removeLiquidityAbi = iUniswapV2Router.encodeFunctionData("removeLiquidity", [
      tokenA,
      tokenB,
      liquidity,
      0,
      0,
      poolLogicProxy.address,
      0,
    ]);
    await expect(
      poolLogicProxy.connect(manager).execTransaction(quickswap.router, removeLiquidityAbi),
    ).to.be.revertedWith("UniswapV2Router: EXPIRED");

    const approveABI = iERC20.encodeFunctionData("approve", [quickswap.router, liquidity]);
    await poolLogicProxy.connect(manager).execTransaction(quickswap.pools.usdc_weth.address, approveABI);

    removeLiquidityAbi = iUniswapV2Router.encodeFunctionData("removeLiquidity", [
      tokenA,
      tokenB,
      liquidity,
      0,
      0,
      poolLogicProxy.address,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);

    const lpBalanceBefore = await QuickLPUSDCWETH.balanceOf(poolLogicProxy.address);
    const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
    const wethBalanceBefore = await WETH.balanceOf(poolLogicProxy.address);
    const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

    expect(lpBalanceBefore).to.gt(0);

    await poolLogicProxy.connect(manager).execTransaction(quickswap.router, removeLiquidityAbi);

    checkAlmostSame(await QuickLPUSDCWETH.balanceOf(poolLogicProxy.address), liquidity);
    expect(await USDC.balanceOf(poolLogicProxy.address)).to.be.gt(usdcBalanceBefore);
    expect(await WETH.balanceOf(poolLogicProxy.address)).to.be.gt(wethBalanceBefore);
    checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
  });

  // Removed OpenAssetGuard - needs to be reinstated securely
  it.skip("Should be able to approve non-supported asset", async () => {
    // transfer wmatic for testing
    const depositAmount = units(500);
    await WMATIC.deposit({ value: depositAmount });
    await WMATIC.transfer(poolLogicProxy.address, depositAmount);

    let approveABI = iERC20.encodeFunctionData("approve", [assets.dai, depositAmount]);

    await expect(poolLogicProxy.connect(manager).execTransaction(assets.dai, approveABI)).to.be.revertedWith(
      "asset not enabled in pool",
    );

    approveABI = iERC20.encodeFunctionData("approve", [quickswap.router, depositAmount]);
    await poolLogicProxy.connect(manager).execTransaction(assets.wmatic, approveABI);
  });

  // Removed OpenAssetGuard - needs to be reinstated securely
  it.skip("Should be able to swap non-supported asset", async () => {
    const sourceAmount = units(100);
    const swapABI = iQuickswapRouter.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      0,
      [assets.wmatic, assets.weth],
      poolLogicProxy.address,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);

    const wethBalanceBefore = await WETH.balanceOf(poolLogicProxy.address);

    await poolLogicProxy.connect(manager).execTransaction(quickswap.router, swapABI);

    const wethBalanceAfter = await WETH.balanceOf(poolLogicProxy.address);
    expect(wethBalanceAfter).gt(wethBalanceBefore);
  });

  // Removed OpenAssetGuard - needs to be reinstated securely
  it.skip("Should be able to swap non-supported asset (routing)", async () => {
    const sourceAmount = units(100);
    const swapABI = iQuickswapRouter.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      0,
      [assets.wmatic, assets.quick, assets.weth],
      poolLogicProxy.address,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);

    const wethBalanceBefore = await WETH.balanceOf(poolLogicProxy.address);

    await poolLogicProxy.connect(manager).execTransaction(quickswap.router, swapABI);

    const wethBalanceAfter = await WETH.balanceOf(poolLogicProxy.address);
    expect(wethBalanceAfter).gt(wethBalanceBefore);
  });

  it("should be able to stake lp(USDC/WETH) on quickswap.", async () => {
    const liquidity = await QuickLPUSDCWETH.balanceOf(poolLogicProxy.address);

    const approveABI = iERC20.encodeFunctionData("approve", [quickswap.pools.usdc_weth.stakingRewards, liquidity]);
    await poolLogicProxy.connect(manager).execTransaction(quickswap.pools.usdc_weth.address, approveABI);

    const stakeABI = iStakingRewards.encodeFunctionData("stake", [liquidity]);

    const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
    expect(liquidity).to.gt(0);

    await poolLogicProxy.connect(manager).execTransaction(quickswap.pools.usdc_weth.stakingRewards, stakeABI);

    expect(await QuickLPUSDCWETH.balanceOf(poolLogicProxy.address)).to.equal(0);
    checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
  });

  // Doesn't seem to be getting any rewards
  it.skip("should be able to claim rewards from quickswap.", async () => {
    const claimABI = iStakingRewards.encodeFunctionData("getReward", []);

    const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
    expect(await QUICK.balanceOf(poolLogicProxy.address)).to.equal(0);

    await poolLogicProxy.connect(manager).execTransaction(quickswap.pools.usdc_weth.stakingRewards, claimABI);

    expect(await QUICK.balanceOf(poolLogicProxy.address)).to.gt(0);
    checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
  });

  it("should be able to withdraw lp(USDC/WETH) on quickswap.", async () => {
    const liquidity = await poolManagerLogicProxy.assetBalance(quickswap.pools.usdc_weth.address);
    const withdrawABI = iStakingRewards.encodeFunctionData("withdraw", [liquidity]);

    const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
    expect(await QuickLPUSDCWETH.balanceOf(poolLogicProxy.address)).to.equal(0);
    expect(liquidity).to.gt(0);

    await poolLogicProxy.connect(manager).execTransaction(quickswap.pools.usdc_weth.stakingRewards, withdrawABI);

    expect(await QuickLPUSDCWETH.balanceOf(poolLogicProxy.address)).to.equal(liquidity);
    checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
  });
});
