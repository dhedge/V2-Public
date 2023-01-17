import { ethers } from "hardhat";
import { solidity } from "ethereum-waffle";
import { expect, use } from "chai";
import axios from "axios";

import { ovmChainData } from "../../../config/chainData/ovm-data";
const { assets, price_feeds, velodrome } = ovmChainData;
import { utils } from "../utils/utils";

use(solidity);

describe("VelodromeTWAPAggregator Test", function () {
  let snapId: string;
  before(async () => {
    snapId = await utils.evmTakeSnap();
  });

  after(async () => {
    await utils.evmRestoreSnap(snapId);
  });

  it("Check velo price", async () => {
    const VelodromeTWAPAggregator = await ethers.getContractFactory("VelodromeTWAPAggregator");
    const velodromeTwapAggregator = await VelodromeTWAPAggregator.deploy(
      velodrome.VARIABLE_VELO_USDC.poolAddress,
      velodrome.velo,
      assets.usdc,
      price_feeds.usdc,
    );
    await velodromeTwapAggregator.deployed();

    const price = (await velodromeTwapAggregator.latestRoundData())[1];
    console.log("price = ", price.toString());
    const priceFromCoingecko = ethers.utils.parseUnits(
      (await getTokenPriceFromCoingecko(velodrome.velo)).toString(),
      8,
    );
    console.log("priceFromCoingecko = ", priceFromCoingecko.toString());
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    expect(price).to.be.closeTo(priceFromCoingecko, price.mul(5).div(100) as any); // 5% diff
  });
});

const getTokenPriceFromCoingecko = async (tokenAddr: string) => {
  const apiUrl = `https://api.coingecko.com/api/v3/simple/token_price/optimistic-ethereum?contract_addresses=${tokenAddr}&vs_currencies=usd`;
  const response = await axios.get(apiUrl);
  return response.data[tokenAddr.toLocaleLowerCase()].usd;
};
