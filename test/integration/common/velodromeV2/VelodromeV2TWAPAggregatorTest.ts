import { ethers } from "hardhat";
import { expect } from "chai";

import { getTokenPriceFromCoingecko } from "../../utils/coingecko/getTokenPrice";

type ITWAPTestParams = {
  assetToTest: string;
  veloV2Pair: string;
  pairAsset: string;
  pairAssetPriceFeed: string;
  coingeckoChainId: Parameters<typeof getTokenPriceFromCoingecko>[1];
};

export const runTests = (testParams: ITWAPTestParams[]) => {
  describe("VelodromeV2TWAPAggregator Test", () => {
    testParams.forEach(({ assetToTest, veloV2Pair, pairAsset, pairAssetPriceFeed, coingeckoChainId }) => {
      it("should calculate price correctly", async () => {
        const VelodromeTWAPAggregator = await ethers.getContractFactory("VelodromeV2TWAPAggregator");
        const velodromeTwapAggregator = await VelodromeTWAPAggregator.deploy(
          veloV2Pair,
          assetToTest,
          pairAsset,
          pairAssetPriceFeed,
        );
        await velodromeTwapAggregator.deployed();

        const price = (await velodromeTwapAggregator.latestRoundData())[1];
        console.log("price = ", price.toString());
        const priceFromCoingecko = ethers.utils.parseUnits(
          (await getTokenPriceFromCoingecko(assetToTest, coingeckoChainId)).toString(),
          8,
        );
        console.log("priceFromCoingecko = ", priceFromCoingecko.toString());

        expect(price).to.be.closeTo(priceFromCoingecko, priceFromCoingecko.div(100)); // 1%
      });
    });
  });
};
