import { ethers } from "hardhat";
import { solidity } from "ethereum-waffle";
import { expect, use } from "chai";
import axios from "axios";

import { uniswapV3, assets, price_feeds } from "./ovm-data";
import { UniV3TWAPAggregator } from "../../../types";

use(solidity);

describe("UniV3TWAPAggregator Test", function () {
  let uniV3TwapAggregator: UniV3TWAPAggregator;

  it("Check price lower limit", async () => {
    const UniV3TWAPAggregator = await ethers.getContractFactory("UniV3TWAPAggregator");
    uniV3TwapAggregator = await UniV3TWAPAggregator.deploy(
      uniswapV3.pools.susd_dai,
      assets.susd,
      price_feeds.dai,
      102000000, // $1.02
      104000000, // $1.04
      60 * 10, // 10 mins update interval
    );
    await uniV3TwapAggregator.deployed();

    await expect(uniV3TwapAggregator.latestRoundData()).to.revertedWith("answer exceeds lower limit");
  });

  it("Check price upper limit", async () => {
    const UniV3TWAPAggregator = await ethers.getContractFactory("UniV3TWAPAggregator");
    uniV3TwapAggregator = await UniV3TWAPAggregator.deploy(
      uniswapV3.pools.susd_dai,
      assets.susd,
      price_feeds.dai,
      96000000, // $0.96
      98000000, // $0.98
      60 * 10, // 10 mins update interval
    );
    await uniV3TwapAggregator.deployed();

    await expect(uniV3TwapAggregator.latestRoundData()).to.revertedWith("answer exceeds upper limit");
  });

  it("Get sUSD price", async () => {
    const UniV3TWAPAggregator = await ethers.getContractFactory("UniV3TWAPAggregator");
    uniV3TwapAggregator = await UniV3TWAPAggregator.deploy(
      uniswapV3.pools.susd_dai,
      assets.susd,
      price_feeds.dai,
      98000000, // $0.98 lower limit
      102000000, // $1.02 upper limit
      60 * 10, // 10 mins update interval
    );
    await uniV3TwapAggregator.deployed();

    const price = (await uniV3TwapAggregator.latestRoundData()).answer;
    const priceFromCoingecko = ethers.utils.parseUnits((await getTokenPriceFromCoingecko(assets.susd)).toString(), 8);
    expect(price).to.be.closeTo(priceFromCoingecko, price.mul(2).div(100) as any); // 2% diff
  });
});

const getTokenPriceFromCoingecko = async (tokenAddr: string) => {
  const apiUrl = `https://api.coingecko.com/api/v3/simple/token_price/optimistic-ethereum?contract_addresses=${tokenAddr}&vs_currencies=usd`;
  const response = await axios.get(apiUrl);
  return response.data[tokenAddr.toLocaleLowerCase()].usd;
};
