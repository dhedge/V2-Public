import { ethers } from "hardhat";
import { solidity } from "ethereum-waffle";
import { expect, use } from "chai";
import axios from "axios";

import { checkAlmostSame, units } from "../../TestHelpers";
import { assets, price_feeds, eth_price_feeds, sushi } from "../polygon-data";
import { MedianTWAPAggregator } from "../../../types";

use(solidity);

describe("ETHCrossAggregator Test", function () {
  let dhedgeMedianTwapAggregator: MedianTWAPAggregator;

  beforeEach(async function () {
    const MedianTWAPAggregator = await ethers.getContractFactory("MedianTWAPAggregator");
    dhedgeMedianTwapAggregator = await MedianTWAPAggregator.deploy(
      sushi.pools.weth_dht.address,
      assets.dht,
      price_feeds.eth,
      1000,
      assets.usdc,
      units(10), // 10 USDC
    );
    await dhedgeMedianTwapAggregator.deployed();
  });

  it("Get Dhedge price", async () => {
    await dhedgeMedianTwapAggregator.update();
    await ethers.provider.send("evm_increaseTime", [2000]);
    await dhedgeMedianTwapAggregator.update();
    await ethers.provider.send("evm_increaseTime", [2000]);
    await dhedgeMedianTwapAggregator.update();
    await ethers.provider.send("evm_increaseTime", [2000]);
    await dhedgeMedianTwapAggregator.update();

    const price = (await dhedgeMedianTwapAggregator.latestRoundData()).answer;
    console.log(price.toString());
    const priceFromCongecko = ethers.utils.parseUnits((await getTokenPriceFromCoingecko(assets.dht)).toString(), 8);
    console.log(priceFromCongecko.toString());
    expect(price).to.be.closeTo(priceFromCongecko, price.mul(3).div(100) as any); // 3% diff
  });

  it("Get WETH price", async () => {
    const MedianTWAPAggregator = await ethers.getContractFactory("MedianTWAPAggregator");
    const wethMedianTwapAggregator = await MedianTWAPAggregator.deploy(
      sushi.pools.usdc_weth.address,
      assets.weth,
      price_feeds.usdc,
      1000,
      assets.usdc,
      units(10), // 10 USDC
    );
    await wethMedianTwapAggregator.deployed();

    await wethMedianTwapAggregator.update();
    await ethers.provider.send("evm_increaseTime", [2000]);
    await wethMedianTwapAggregator.update();
    await ethers.provider.send("evm_increaseTime", [2000]);
    await wethMedianTwapAggregator.update();
    await ethers.provider.send("evm_increaseTime", [2000]);
    await wethMedianTwapAggregator.update();

    const price = (await wethMedianTwapAggregator.latestRoundData()).answer;
    console.log(price.toString());
    const priceFromCongecko = ethers.utils.parseUnits((await getTokenPriceFromCoingecko(assets.weth)).toString(), 8);
    console.log(priceFromCongecko.toString());
    expect(price).to.be.closeTo(priceFromCongecko, price.mul(3).div(100) as any); // 3% diff
  });

  it("Get USDC price", async () => {
    const MedianTWAPAggregator = await ethers.getContractFactory("MedianTWAPAggregator");
    const usdcMedianTwapAggregator = await MedianTWAPAggregator.deploy(
      sushi.pools.usdc_weth.address,
      assets.usdc,
      price_feeds.eth,
      1000,
      assets.usdc,
      units(10), // 10 USDC
    );
    await usdcMedianTwapAggregator.deployed();

    await usdcMedianTwapAggregator.update();
    await ethers.provider.send("evm_increaseTime", [2000]);
    await usdcMedianTwapAggregator.update();
    await ethers.provider.send("evm_increaseTime", [2000]);
    await usdcMedianTwapAggregator.update();
    await ethers.provider.send("evm_increaseTime", [2000]);
    await usdcMedianTwapAggregator.update();

    const price = (await usdcMedianTwapAggregator.latestRoundData()).answer;
    console.log(price.toString());
    const priceFromCongecko = ethers.utils.parseUnits((await getTokenPriceFromCoingecko(assets.usdc)).toString(), 8);
    console.log(priceFromCongecko.toString());
    expect(price).to.be.closeTo(priceFromCongecko, price.mul(3).div(100) as any); // 3% diff
  });
});

const getTokenPriceFromCoingecko = async (tokenAddr: string) => {
  const apiUrl = `https://api.coingecko.com/api/v3/simple/token_price/polygon-pos?contract_addresses=${tokenAddr}&vs_currencies=usd`;
  const response = await axios.get(apiUrl);
  return response.data[tokenAddr.toLocaleLowerCase()].usd;
};
