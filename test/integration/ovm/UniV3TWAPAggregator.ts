import { ethers } from "hardhat";
import { solidity } from "ethereum-waffle";
import { expect, use } from "chai";
import axios from "axios";

import { uniswapV3, assets, price_feeds } from "./ovm-data";
import { UniV3TWAPAggregator } from "../../../types";

use(solidity);

describe("UniV3TWAPAggregator Test", function () {
  let uniV3TwapAggregator: UniV3TWAPAggregator;

  beforeEach(async function () {
    const UniV3TWAPAggregator = await ethers.getContractFactory("UniV3TWAPAggregator");
    uniV3TwapAggregator = await UniV3TWAPAggregator.deploy(
      uniswapV3.pools.susd_dai,
      assets.susd,
      price_feeds.dai,
      60 * 10, // 10 mins update interval
    );
    await uniV3TwapAggregator.deployed();
  });

  it("Get sUSD price", async () => {
    const price = (await uniV3TwapAggregator.latestRoundData()).answer;
    const priceFromCongecko = ethers.utils.parseUnits((await getTokenPriceFromCoingecko(assets.susd)).toString(), 8);
    expect(price).to.be.closeTo(priceFromCongecko, price.mul(2).div(100) as any); // 2% diff
  });
});

const getTokenPriceFromCoingecko = async (tokenAddr: string) => {
  const apiUrl = `https://api.coingecko.com/api/v3/simple/token_price/optimistic-ethereum?contract_addresses=${tokenAddr}&vs_currencies=usd`;
  const response = await axios.get(apiUrl);
  return response.data[tokenAddr.toLocaleLowerCase()].usd;
};
