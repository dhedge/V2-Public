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
  expect(ethers.BigNumber.from(a).gt(ethers.BigNumber.from(b).mul(99).div(100))).to.be.true;
  expect(ethers.BigNumber.from(a).lt(ethers.BigNumber.from(b).mul(101).div(100))).to.be.true;
};

module.exports = { updateChainlinkAggregators, currentBlockTimestamp, checkAlmostSame };
