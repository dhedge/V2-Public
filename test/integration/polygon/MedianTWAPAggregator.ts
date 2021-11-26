import { ethers } from "hardhat";
import { solidity } from "ethereum-waffle";
import { expect, use } from "chai";

import { units } from "../../TestHelpers";
import { assets, price_feeds, eth_price_feeds, sushi } from "../polygon-data";
import { MedianTWAPAggregator } from "../../../types";

use(solidity);

describe("ETHCrossAggregator Test", function () {
  let medianTwapAggregator: MedianTWAPAggregator;

  beforeEach(async function () {
    const MedianTWAPAggregator = await ethers.getContractFactory("MedianTWAPAggregator");
    medianTwapAggregator = await MedianTWAPAggregator.deploy(
      sushi.pools.weth_dht.address,
      assets.dht,
      price_feeds.eth,
      1000,
      assets.usdc,
      units(10), // 10 USDC
    );
    await medianTwapAggregator.deployed();
  });

  it("latestRoundData", async () => {
    await medianTwapAggregator.update();
    await ethers.provider.send("evm_increaseTime", [2000]);
    await medianTwapAggregator.update();
    await ethers.provider.send("evm_increaseTime", [2000]);
    await medianTwapAggregator.update();
    await ethers.provider.send("evm_increaseTime", [2000]);
    await medianTwapAggregator.update();

    const res = await medianTwapAggregator.latestRoundData();
    console.log(res.answer.toString());
  });
});
