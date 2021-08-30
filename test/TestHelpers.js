const { expect } = require("chai");

const currentBlockTimestamp = async () => {
  const currentBlockNumber = await ethers.provider.getBlockNumber();
  return (await ethers.provider.getBlock(currentBlockNumber)).timestamp;
};

const updateChainlinkAggregators = async (usd_price_feed, eth_price_feed, link_price_feed) => {
  const MockContract = await ethers.getContractFactory("MockContract");

  const AggregatorV3 = await hre.artifacts.readArtifact("AggregatorV3Interface");
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

const checkAlmostSame = (a, b) => {
  expect(ethers.BigNumber.from(a).gte(ethers.BigNumber.from(b).mul(99).div(100))).to.be.true;
  expect(ethers.BigNumber.from(a).lte(ethers.BigNumber.from(b).mul(101).div(100))).to.be.true;
};

const approxEq = (v1, v2, diff = 0.01) => Math.abs(1 - v1 / v2) <= diff;

/// Converts a string into a hex representation of bytes32
const toBytes32 = (key) => ethers.utils.formatBytes32String(key);

const getAmountOut = async (routerAddress, amountIn, path) => {
  const IUniswapV2Router = await hre.artifacts.readArtifact("IUniswapV2Router");
  const router = await ethers.getContractAt(IUniswapV2Router.abi, routerAddress);
  const amountsOut = await router.getAmountsOut(amountIn, path);
  return amountsOut[amountsOut.length - 1];
};

const getAmountIn = async (routerAddress, amountOut, path) => {
  const IUniswapV2Router = await hre.artifacts.readArtifact("IUniswapV2Router");
  const router = await ethers.getContractAt(IUniswapV2Router.abi, routerAddress);
  const amountsIn = await router.getAmountsIn(amountOut, path);
  return amountsIn[0];
};

const units = (amount, decimal = 18) => {
  return ethers.BigNumber.from(amount.toString()).mul(ethers.BigNumber.from(10).pow(decimal));
};

module.exports = {
  updateChainlinkAggregators,
  currentBlockTimestamp,
  checkAlmostSame,
  approxEq,
  toBytes32,
  getAmountOut,
  getAmountIn,
  units,
};
