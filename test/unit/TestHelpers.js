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

module.exports = { updateChainlinkAggregators, currentBlockTimestamp };
