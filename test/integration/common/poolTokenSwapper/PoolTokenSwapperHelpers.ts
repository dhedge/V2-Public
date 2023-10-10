import { expect } from "chai";
import { ethers } from "hardhat";
import { BigNumber } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import { units } from "../../../testHelpers";
import { PoolTokenSwapperTestParameters } from "./PoolTokenSwapperSwapTest";
import { PoolLogic, PoolTokenSwapper, IERC20Extended, PoolFactory } from "../../../../types";

export const FEE_DENOMINATOR = 10_000;

export const depositAssetToPool = async (
  user: SignerWithAddress,
  depositAsset: IERC20Extended,
  pool: PoolLogic,
  depositAmount: BigNumber,
): Promise<BigNumber> => {
  await depositAsset.connect(user).approve(pool.address, depositAmount);
  await pool.connect(user).deposit(depositAsset.address, depositAmount);

  const poolTokenBalance = await pool.balanceOf(user.address);
  return poolTokenBalance;
};

export const swapAssetToPoolToken = async (
  user: SignerWithAddress,
  poolTokenSwapper: PoolTokenSwapper,
  from: IERC20Extended,
  to: PoolLogic,
  swapAmount: BigNumber,
  poolFactory: PoolFactory,
  swapFee: number,
  minAmountOut = BigNumber.from(0),
) => {
  // Get balances before
  const userFromBalanceBefore = await from.balanceOf(user.address);
  const userToBalanceBefore = await to.balanceOf(user.address);
  const swapperFromBalanceBefore = await from.balanceOf(poolTokenSwapper.address);
  const swapperToBalanceBefore = await to.balanceOf(poolTokenSwapper.address);

  // Swap from asset to pool token
  await from.connect(user).approve(poolTokenSwapper.address, swapAmount);
  await poolTokenSwapper.connect(user).swap(from.address, to.address, swapAmount, minAmountOut);

  // Get balances after
  const userFromBalanceAfter = await from.balanceOf(user.address);
  const userToBalanceAfter = await to.balanceOf(user.address);
  const swapperFromBalanceAfter = await from.balanceOf(poolTokenSwapper.address);
  const swapperToBalanceAfter = await to.balanceOf(poolTokenSwapper.address);

  // Get values for checks
  const fromAssetDecimals = await from.decimals();
  const fromAssetPrice18 = await poolFactory.getAssetPrice(from.address);
  const swapValue18 = swapAmount.mul(fromAssetPrice18).div(units(1, fromAssetDecimals));
  const poolTokenPrice18 = await to.tokenPrice();
  let expectedReceivedPoolTokens = swapValue18.mul(units(1)).div(poolTokenPrice18);
  const feeAmount = expectedReceivedPoolTokens.mul(swapFee).div(FEE_DENOMINATOR);
  expectedReceivedPoolTokens = expectedReceivedPoolTokens.sub(feeAmount);

  // Check swap fee
  expect(swapFee).to.be.gt(0);
  expect(feeAmount).to.be.lt(expectedReceivedPoolTokens.div(100)); // swap fee should be small
  // Check that swaps are directionally correct
  expect(userToBalanceAfter).to.gt(userToBalanceBefore);
  expect(swapperToBalanceAfter).to.lt(swapperToBalanceBefore);
  expect(userFromBalanceAfter).to.lt(userFromBalanceBefore);
  expect(swapperFromBalanceAfter).to.gt(swapperFromBalanceBefore);
  // Check that expected swap amounts are correct
  expect(userFromBalanceAfter).to.eq(userFromBalanceBefore.sub(swapAmount));
  expect(swapperFromBalanceAfter).to.eq(swapperFromBalanceBefore.add(swapAmount));
  expect(expectedReceivedPoolTokens).to.be.closeTo(
    swapperToBalanceBefore.sub(swapperToBalanceAfter),
    swapValue18.div(units(1)), // should basically just be a single digit rounding error
  );
};

export const swapPoolTokenToAsset = async (
  user: SignerWithAddress,
  poolTokenSwapper: PoolTokenSwapper,
  from: PoolLogic,
  to: IERC20Extended,
  swapAmount: BigNumber,
  poolFactory: PoolFactory,
  swapFee: number,
  minAmountOut = BigNumber.from(0),
) => {
  // Get balances before
  const userFromBalanceBefore = await from.balanceOf(user.address);
  const userToBalanceBefore = await to.balanceOf(user.address);
  const swapperFromBalanceBefore = await from.balanceOf(poolTokenSwapper.address);
  const swapperToBalanceBefore = await to.balanceOf(poolTokenSwapper.address);

  // Swap from asset to pool token
  await from.connect(user).approve(poolTokenSwapper.address, swapAmount);
  await poolTokenSwapper.connect(user).swap(from.address, to.address, swapAmount, minAmountOut);

  // Get balances after
  const userFromBalanceAfter = await from.balanceOf(user.address);
  const userToBalanceAfter = await to.balanceOf(user.address);
  const swapperFromBalanceAfter = await from.balanceOf(poolTokenSwapper.address);
  const swapperToBalanceAfter = await to.balanceOf(poolTokenSwapper.address);

  // Get values for checks
  const toAssetDecimals = await to.decimals();
  const toAssetPrice18 = await poolFactory.getAssetPrice(to.address);
  const poolTokenPrice18 = await from.tokenPrice();
  const swapValue18 = swapAmount.mul(poolTokenPrice18).div(units(1));
  let expectedReceivedAssetTokens = swapValue18.mul(units(1, toAssetDecimals)).div(toAssetPrice18);
  const feeAmount = expectedReceivedAssetTokens.mul(swapFee).div(FEE_DENOMINATOR);
  expectedReceivedAssetTokens = expectedReceivedAssetTokens.sub(feeAmount);

  // Check swap fee
  expect(swapFee).to.be.gt(0);
  expect(feeAmount).to.be.lt(expectedReceivedAssetTokens.div(100)); // swap fee should be small
  // Check that swaps are directionally correct
  expect(userToBalanceAfter).to.gt(userToBalanceBefore);
  expect(swapperToBalanceAfter).to.lt(swapperToBalanceBefore);
  expect(userFromBalanceAfter).to.lt(userFromBalanceBefore);
  expect(swapperFromBalanceAfter).to.gt(swapperFromBalanceBefore);
  // Check that expected swap amounts are correct
  expect(userFromBalanceAfter).to.eq(userFromBalanceBefore.sub(swapAmount));
  expect(swapperFromBalanceAfter).to.eq(swapperFromBalanceBefore.add(swapAmount));
  expect(expectedReceivedAssetTokens).to.be.closeTo(
    swapperToBalanceBefore.sub(swapperToBalanceAfter),
    swapValue18.div(units(1)), // should basically just be a single digit rounding error
  );
};

export const swapPoolTokenToPoolToken = async (
  user: SignerWithAddress,
  poolTokenSwapper: PoolTokenSwapper,
  from: PoolLogic,
  to: PoolLogic,
  swapAmount: BigNumber,
  _: PoolFactory,
  swapFee: number,
  minAmountOut = BigNumber.from(0),
) => {
  // Get balances before
  const userFromBalanceBefore = await from.balanceOf(user.address);
  const userToBalanceBefore = await to.balanceOf(user.address);
  const swapperFromBalanceBefore = await from.balanceOf(poolTokenSwapper.address);
  const swapperToBalanceBefore = await to.balanceOf(poolTokenSwapper.address);

  // Swap from asset to pool token
  await from.connect(user).approve(poolTokenSwapper.address, swapAmount);
  await poolTokenSwapper.connect(user).swap(from.address, to.address, swapAmount, minAmountOut);

  // Get balances after
  const userFromBalanceAfter = await from.balanceOf(user.address);
  const userToBalanceAfter = await to.balanceOf(user.address);
  const swapperFromBalanceAfter = await from.balanceOf(poolTokenSwapper.address);
  const swapperToBalanceAfter = await to.balanceOf(poolTokenSwapper.address);

  // Get values for checks
  const fromPoolTokenPrice18 = await from.tokenPrice();
  const toPoolTokenPrice18 = await to.tokenPrice();
  const swapValue18 = swapAmount.mul(fromPoolTokenPrice18).div(units(1));
  let expectedReceivedPoolTokens = swapValue18.mul(units(1, 18)).div(toPoolTokenPrice18);
  const feeAmount = expectedReceivedPoolTokens.mul(swapFee).div(FEE_DENOMINATOR);
  expectedReceivedPoolTokens = expectedReceivedPoolTokens.sub(feeAmount);

  // Check swap fee
  expect(swapFee).to.be.gt(0);
  expect(feeAmount).to.be.lt(expectedReceivedPoolTokens.div(100)); // swap fee should be small
  // Check that swaps are directionally correct
  expect(userToBalanceAfter).to.gt(userToBalanceBefore);
  expect(swapperToBalanceAfter).to.lt(swapperToBalanceBefore);
  expect(userFromBalanceAfter).to.lt(userFromBalanceBefore);
  expect(swapperFromBalanceAfter).to.gt(swapperFromBalanceBefore);
  // Check that expected swap amounts are correct
  expect(userFromBalanceAfter).to.eq(userFromBalanceBefore.sub(swapAmount));
  expect(swapperFromBalanceAfter).to.eq(swapperFromBalanceBefore.add(swapAmount));
  expect(expectedReceivedPoolTokens).to.be.closeTo(
    swapperToBalanceBefore.sub(swapperToBalanceAfter),
    swapValue18.div(units(1)), // should basically just be a single digit rounding error
  );
};

export const getPoolTokenSwapperConfig = (assetsEnabled: string[], poolsEnabled: string[], poolSwapFees: number[]) => {
  expect(poolsEnabled.length == poolSwapFees.length);

  const assetConfig: { asset: string; assetEnabled: boolean }[] = [];
  for (let i = 0; i < assetsEnabled.length; i++) {
    assetConfig[i] = { asset: assetsEnabled[i], assetEnabled: true };
  }

  const poolConfig: { pool: string; poolSwapFee: string; poolEnabled: boolean }[] = [];
  for (let i = 0; i < poolsEnabled.length; i++) {
    poolConfig[i] = { pool: poolsEnabled[i], poolSwapFee: poolSwapFees[i].toString(), poolEnabled: true };
  }

  return { assetConfig, poolConfig };
};

export const getAssetToPoolSwapParams = async (
  swapFrom: PoolTokenSwapperTestParameters["swapFrom"],
  swapTo: PoolTokenSwapperTestParameters["swapTo"],
) => {
  const PoolLogic = await ethers.getContractFactory("PoolLogic");
  const fromAsset = await ethers.getContractAt("IERC20Extended", swapFrom.address);
  const toAsset = PoolLogic.attach(swapTo.address);
  const swapFee = swapTo.swapFee ? swapTo.swapFee : 0;

  return { fromAsset, toAsset, swapFee };
};

export const getPoolToAssetSwapParams = async (
  swapFrom: PoolTokenSwapperTestParameters["swapFrom"],
  swapTo: PoolTokenSwapperTestParameters["swapTo"],
) => {
  const PoolLogic = await ethers.getContractFactory("PoolLogic");
  const fromAsset = PoolLogic.attach(swapFrom.address);
  const toAsset = await ethers.getContractAt("IERC20Extended", swapTo.address);
  const swapFee = swapFrom.swapFee ? swapFrom.swapFee : 0;

  return { fromAsset, toAsset, swapFee };
};

export const getPoolToPoolSwapParams = async (
  swapFrom: PoolTokenSwapperTestParameters["swapFrom"],
  swapTo: PoolTokenSwapperTestParameters["swapTo"],
) => {
  const PoolLogic = await ethers.getContractFactory("PoolLogic");
  const fromAsset = PoolLogic.attach(swapFrom.address);
  const toAsset = PoolLogic.attach(swapTo.address);

  // select max swap fee of both assets to be used for the swap
  const fromSwapFee = swapFrom.swapFee ? swapFrom.swapFee : 0;
  const toSwapFee = swapTo.swapFee ? swapTo.swapFee : 0;
  const swapFee = fromSwapFee >= toSwapFee ? fromSwapFee : toSwapFee;

  return { fromAsset, toAsset, swapFee };
};
