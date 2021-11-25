const { ethers } = require("hardhat");
const { expect } = require("chai");
const { price_feeds } = require("../polygon-data");

describe("SynthPriceAggregator Test", function () {
  let ethUsdAggregator;

  before(async function () {
    const USDPriceAggregator = await ethers.getContractFactory("USDPriceAggregator");
    usdPriceAggregator = await USDPriceAggregator.deploy();
    usdPriceAggregator.deployed();

    const SynthPriceAggregator = await ethers.getContractFactory("SynthPriceAggregator");
    synthPriceAggregator = await SynthPriceAggregator.deploy(usdPriceAggregator.address, price_feeds.eth);
    synthPriceAggregator.deployed();

    ethUsdAggregator = await ethers.getContractAt("IAggregatorV3Interface", price_feeds.eth);
  });

  it("Should be able to get Price", async function () {
    const { answer: ethUsdPrice } = await ethUsdAggregator.latestRoundData();
    const { answer: synthUsdPrice } = await synthPriceAggregator.latestRoundData();

    expect(ethUsdPrice).to.equal(synthUsdPrice);
  });
});
