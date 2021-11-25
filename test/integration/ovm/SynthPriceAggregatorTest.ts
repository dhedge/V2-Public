import { IAggregatorV3Interface } from "../../../types/IAggregatorV3Interface";

import { ethers } from "hardhat";
import { expect } from "chai";
import { price_feeds } from "./ovm-data";

describe("SynthPriceAggregator Test", function () {
  let ethUsdAggregator: IAggregatorV3Interface;
  let usdPriceAggregator: IAggregatorV3Interface;
  let synthPriceAggregator: IAggregatorV3Interface;

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
    const { answer: usdPrice } = await usdPriceAggregator.latestRoundData();

    expect(usdPrice).to.equal(1e8);
    expect(ethUsdPrice).to.equal(synthUsdPrice);
  });
});
