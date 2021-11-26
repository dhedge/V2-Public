const { ethers } = require("hardhat");
const { expect, use } = require("chai");
const chaiAlmost = require("chai-almost");
const { units } = require("../../TestHelpers");
const { assets, price_feeds, eth_price_feeds } = require("../polygon-data");

use(chaiAlmost());

describe("ETHCrossAggregator Test", function () {
  let ethUsdAggregator;
  let ghstEthAggregator;
  let ghstUsdAggregator;

  before(async function () {
    const ETHCrossAggregator = await ethers.getContractFactory("ETHCrossAggregator");
    ghstUsdAggregator = await ETHCrossAggregator.deploy(assets.ghst, eth_price_feeds.ghst, price_feeds.eth);
    ghstUsdAggregator.deployed();

    ethUsdAggregator = await ethers.getContractAt("IAggregatorV3Interface", price_feeds.eth);
    ghstEthAggregator = await ethers.getContractAt("IAggregatorV3Interface", eth_price_feeds.ghst);
  });

  it("Should be able to get Price", async function () {
    const { answer: ethUsdPrice } = await ethUsdAggregator.latestRoundData();
    const { answer: ghstEthPrice } = await ghstEthAggregator.latestRoundData();
    const { answer: ghstUsdPrice } = await ghstUsdAggregator.latestRoundData();

    console.log("ETH/USD price:", ethUsdPrice.toString());
    console.log("GHST/ETH price:", ghstEthPrice.toString());
    console.log("GHST/USD price:", ghstUsdPrice.toString());
    expect(ghstUsdPrice).to.equal(ethUsdPrice.mul(ghstEthPrice).div(units(1)));
  });
});
