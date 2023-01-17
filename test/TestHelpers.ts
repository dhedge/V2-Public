import { artifacts, ethers } from "hardhat";
import { BigNumber, BigNumberish } from "ethers";
import { MockContract } from "../types";
import { expect } from "chai";

export const currentBlockTimestamp = async () => {
  const currentBlockNumber = await ethers.provider.getBlockNumber();
  return (await ethers.provider.getBlock(currentBlockNumber)).timestamp;
};

export const updateChainlinkAggregators = async (
  usd_price_feed: MockContract,
  eth_price_feed: MockContract,
  link_price_feed: MockContract,
) => {
  const AggregatorV3 = await artifacts.readArtifact("AggregatorV3Interface");
  const iAggregatorV3 = new ethers.utils.Interface(AggregatorV3.abi);
  const latestRoundDataABI = iAggregatorV3.encodeFunctionData("latestRoundData", []);
  const current = await currentBlockTimestamp();
  await usd_price_feed.givenCalldataReturn(
    latestRoundDataABI,
    ethers.utils.solidityPack(["uint256", "int256", "uint256", "uint256", "uint256"], [0, 100000000, 0, current, 0]),
  ); // $1
  await eth_price_feed.givenCalldataReturn(
    latestRoundDataABI,
    ethers.utils.solidityPack(["uint256", "int256", "uint256", "uint256", "uint256"], [0, 200000000000, 0, current, 0]),
  ); // $2000
  await link_price_feed.givenCalldataReturn(
    latestRoundDataABI,
    ethers.utils.solidityPack(["uint256", "int256", "uint256", "uint256", "uint256"], [0, 3500000000, 0, current, 0]),
  ); // $35
};

// Within 1%
// @deprecated - don't use this - use closeTo with a delta that's geared for the test
// 1% is not an ok spread for some tests
export const checkAlmostSame = (a: BigNumber, b: BigNumberish, percentDelta = 1) => {
  expect(ethers.BigNumber.from(a.toString())).to.be.closeTo(
    ethers.BigNumber.from(b.toString()),
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    a.div(100 / percentDelta) as any,
  );
};

export const checkDelta = (a: BigNumber, b: BigNumberish, difference: BigNumber) => {
  expect(ethers.BigNumber.from(a.toString())).to.be.closeTo(
    ethers.BigNumber.from(b.toString()),
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    difference,
  );
};

export const approxEq = (v1: number, v2: number, diff = 0.01) => Math.abs(1 - v1 / v2) <= diff;

/// Converts a string into a hex representation of bytes32
export const toBytes32 = (key: string) => ethers.utils.formatBytes32String(key);

export const getAmountOut = async (routerAddress: string, amountIn: BigNumber | string, path: string[]) => {
  const IUniswapV2Router = await artifacts.readArtifact("IUniswapV2Router");
  const router = await ethers.getContractAt(IUniswapV2Router.abi, routerAddress);
  const amountsOut = await router.getAmountsOut(amountIn, path);
  return amountsOut[amountsOut.length - 1];
};

export const getAmountIn = async (routerAddress: string, amountOut: BigNumber | string, path: string[]) => {
  const IUniswapV2Router = await artifacts.readArtifact("IUniswapV2Router");
  const router = await ethers.getContractAt(IUniswapV2Router.abi, routerAddress);
  const amountsIn = await router.getAmountsIn(amountOut, path);
  return amountsIn[0];
};

export const units = (amount: number, decimal = 18) => {
  return ethers.BigNumber.from(amount).mul(ethers.BigNumber.from(10).pow(decimal));
};
