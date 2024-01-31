import { ethers } from "hardhat";
import { expect } from "chai";

import { ovmChainData } from "../../../../config/chainData/ovmData";
const { assets, usdPriceFeeds, uniswapV3 } = ovmChainData;
import { UniV3TWAPAggregator } from "../../../../types";
import { utils } from "../../utils/utils";
import { getTokenPriceFromCoingecko } from "../../utils/coingecko/getTokenPrice";

describe("UniV3TWAPAggregator Test", function () {
  let snapId: string;
  before(async () => {
    snapId = await utils.evmTakeSnap();
  });

  after(async () => {
    await utils.evmRestoreSnap(snapId);
  });
  let uniV3TwapAggregator: UniV3TWAPAggregator;

  it("Check price lower limit", async () => {
    const UniV3TWAPAggregator = await ethers.getContractFactory("UniV3TWAPAggregator");
    uniV3TwapAggregator = await UniV3TWAPAggregator.deploy(
      uniswapV3.pools.susd_dai,
      assets.susd,
      usdPriceFeeds.dai,
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
      usdPriceFeeds.dai,
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
      usdPriceFeeds.dai,
      98000000, // $0.98 lower limit
      102000000, // $1.02 upper limit
      60 * 10, // 10 mins update interval
    );
    await uniV3TwapAggregator.deployed();

    const price = (await uniV3TwapAggregator.latestRoundData()).answer;
    const priceFromCoingecko = ethers.utils.parseUnits(
      (await getTokenPriceFromCoingecko(assets.susd, "optimistic-ethereum")).toString(),
      8,
    );
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    expect(price).to.be.closeTo(priceFromCoingecko, price.mul(5).div(100) as any); // 5% diff
  });
});
