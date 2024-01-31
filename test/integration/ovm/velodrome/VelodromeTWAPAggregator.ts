import { ethers } from "hardhat";
import { expect } from "chai";

import { ovmChainData } from "../../../../config/chainData/ovmData";
import { utils } from "../../utils/utils";
import { getTokenPriceFromCoingecko } from "../../utils/coingecko/getTokenPrice";

const { assets, usdPriceFeeds, velodromeV2 } = ovmChainData;

type ITestParam = typeof velodromeV2 & {
  twapAggregatorName: "VelodromeTWAPAggregator" | "VelodromeV2TWAPAggregator";
};

const assetToTest = assets.weth;

const runTests = ({ VARIABLE_WETH_USDC, twapAggregatorName }: ITestParam) => {
  const isV2 = twapAggregatorName === "VelodromeV2TWAPAggregator";
  describe(`Velodrome${isV2 ? "V2" : ""}TWAPAggregator Test`, () => {
    utils.beforeAfterReset(before, after);

    it("should calculate price correctly", async () => {
      const VelodromeTWAPAggregator = await ethers.getContractFactory(twapAggregatorName);
      const velodromeTwapAggregator = await VelodromeTWAPAggregator.deploy(
        VARIABLE_WETH_USDC.poolAddress,
        assetToTest,
        assets.usdc,
        usdPriceFeeds.usdc,
      );
      await velodromeTwapAggregator.deployed();

      const price = (await velodromeTwapAggregator.latestRoundData())[1];
      console.log("price = ", price.toString());
      const priceFromCoingecko = ethers.utils.parseUnits(
        (await getTokenPriceFromCoingecko(assetToTest, "optimistic-ethereum")).toString(),
        8,
      );
      console.log("priceFromCoingecko = ", priceFromCoingecko.toString());

      expect(price).to.be.closeTo(priceFromCoingecko, priceFromCoingecko.div(100)); // 1%
    });
  });
};

[{ ...velodromeV2, twapAggregatorName: "VelodromeV2TWAPAggregator" as const }].forEach(runTests);
