import { ethers } from "hardhat";
import { expect } from "chai";
import { ovmChainData } from "../../../config/chainData/ovmData";
import { IAggregatorV3Interface, SynthPriceAggregator, USDPriceAggregator } from "../../../types";
import { utils } from "../utils/utils";

const { price_feeds } = ovmChainData;

describe("SynthPriceAggregator Test", function () {
  let ethUsdAggregator: IAggregatorV3Interface;
  let usdPriceAggregator: USDPriceAggregator;
  let synthPriceAggregator: SynthPriceAggregator;

  let snapId: string;
  after(async () => {
    await utils.evmRestoreSnap(snapId);
  });

  before(async function () {
    snapId = await utils.evmTakeSnap();
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
    const { answer: synthEthPrice } = await synthPriceAggregator.latestRoundData();
    const { answer: usdPrice } = await usdPriceAggregator.latestRoundData();

    expect(usdPrice).to.equal(1e8);
    expect(synthEthPrice).to.equal(ethUsdPrice);
  });

  it("Adjusts when under 1 dollar", async function () {
    const FixedPriceAggregator = await ethers.getContractFactory("FixedPriceAggregator");
    // 97 cents
    const fixedPriceAggregator = await FixedPriceAggregator.deploy((10 ** 8 / 100) * 97);
    fixedPriceAggregator.deployed();

    const SynthPriceAggregator = await ethers.getContractFactory("SynthPriceAggregator");
    synthPriceAggregator = await SynthPriceAggregator.deploy(fixedPriceAggregator.address, price_feeds.eth);
    synthPriceAggregator.deployed();

    const { answer: ethUsdPrice } = await ethUsdAggregator.latestRoundData();
    const { answer: synthEthPrice } = await synthPriceAggregator.latestRoundData();
    const { answer: fixedPrice } = await fixedPriceAggregator.latestRoundData();

    expect(fixedPrice).to.equal((10 ** 8 / 100) * 97);
    expect(synthEthPrice).to.be.closeTo(
      ethUsdPrice.div(100).mul(97),
      ethUsdPrice.div(100).mul(97).div(1000).toNumber(),
    );
  });

  it("Adjusts when over 1 dollar", async function () {
    const FixedPriceAggregator = await ethers.getContractFactory("FixedPriceAggregator");
    // 103 cents
    const fixedPriceAggregator = await FixedPriceAggregator.deploy((10 ** 8 / 100) * 103);
    fixedPriceAggregator.deployed();

    const SynthPriceAggregator = await ethers.getContractFactory("SynthPriceAggregator");
    synthPriceAggregator = await SynthPriceAggregator.deploy(fixedPriceAggregator.address, price_feeds.eth);
    synthPriceAggregator.deployed();

    const { answer: ethUsdPrice } = await ethUsdAggregator.latestRoundData();
    const { answer: synthEthPrice } = await synthPriceAggregator.latestRoundData();
    const { answer: fixedPrice } = await fixedPriceAggregator.latestRoundData();

    expect(fixedPrice).to.equal((10 ** 8 / 100) * 103);
    expect(synthEthPrice).to.be.closeTo(
      ethUsdPrice.div(100).mul(103),
      ethUsdPrice.div(100).mul(103).div(1000).toNumber(),
    );
  });
});
