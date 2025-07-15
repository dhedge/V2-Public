import { ethers } from "hardhat";
import { expect } from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import { utils } from "../../utils/utils";
import { updatePythPriceFeed } from "../../utils/pyth";
import { checkAlmostSame } from "../../../testHelpers";
import { PythPriceAggregator } from "../../../../types";
import { getTokenPriceFromCoingeckoIds } from "../../utils/coingecko/getTokenPrice";
import { BigNumberish, BytesLike } from "ethers";

interface ITestParams {
  tokenToTest: string;
  pythAddress: string;
  oracleData: IOracleData;
  coingeckoTokenId: string;
}

export interface IOracleData {
  priceId: BytesLike;
  maxAge: BigNumberish;
  minConfidenceRatio: BigNumberish;
}

export const runPythPriceAggregatorTestTest = ({
  tokenToTest,
  pythAddress,
  oracleData,
  coingeckoTokenId,
}: ITestParams) => {
  describe("PythPriceAggregatorTest Test", () => {
    let pythPriceAggregator: PythPriceAggregator;
    let keeper: SignerWithAddress;

    utils.beforeAfterReset(beforeEach, afterEach);

    before(async () => {
      const PythPriceAggregator = await ethers.getContractFactory("PythPriceAggregator");
      pythPriceAggregator = await PythPriceAggregator.deploy(tokenToTest, pythAddress, oracleData);
      await pythPriceAggregator.deployed();

      [keeper] = await ethers.getSigners();
    });

    it("should be able to return price nominated in USD", async () => {
      await updatePythPriceFeed(pythAddress, oracleData.priceId.toString(), keeper);

      const { answer: tokenUsdPrice } = await pythPriceAggregator.latestRoundData();
      const priceFromCoingecko = ethers.utils
        .parseUnits((await getTokenPriceFromCoingeckoIds(coingeckoTokenId)).toString(), 18)
        .div(10 ** (18 - (await pythPriceAggregator.decimals())));
      checkAlmostSame(tokenUsdPrice, priceFromCoingecko, 0.2);
    });

    it("should be able to return valid min and max price", async () => {
      await updatePythPriceFeed(pythAddress, oracleData.priceId.toString(), keeper);
      const { min: min, max: max } = await pythPriceAggregator.getTokenMinMaxPrice(true);

      const priceFromCoingecko = ethers.utils
        .parseUnits((await getTokenPriceFromCoingeckoIds(coingeckoTokenId)).toString(), 18)
        .div(10 ** (18 - (await pythPriceAggregator.decimals())));

      expect(min).lt(priceFromCoingecko);
      expect(max).gt(priceFromCoingecko);
      expect(min.mul(105).div(100)).gt(priceFromCoingecko);
      expect(max.mul(100).div(105)).lt(priceFromCoingecko);
    });

    it("revert when price is stale", async () => {
      await updatePythPriceFeed(pythAddress, oracleData.priceId.toString(), keeper);
      utils.increaseTime(86600);
      await expect(pythPriceAggregator.latestRoundData()).to.be.reverted;
    });
  });
};
