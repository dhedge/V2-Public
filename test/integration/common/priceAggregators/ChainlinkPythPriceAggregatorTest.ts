import { ethers } from "hardhat";
import { expect } from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import { utils } from "../../utils/utils";
import { updatePythPriceFeed } from "../../utils/pyth";
import { checkAlmostSame } from "../../../testHelpers";
import { ChainlinkPythPriceAggregator, IAggregatorV3Interface } from "../../../../types";

interface ITestParams {
  tokenToTest: string;
  pythAddress: string;
  oracleData: IOracleData;
}

export interface IOracleData {
  onchainOracle: {
    oracleContract: string;
    maxAge: number;
  };
  offchainOracle: {
    priceId: string;
    maxAge: number;
    minConfidenceRatio: number;
  };
}

export const runChainlinkPythPriceAggregatorTest = ({ tokenToTest, pythAddress, oracleData }: ITestParams) => {
  describe("ChainlinkPythPriceAggregator Test", () => {
    let chainlinkPythAggregator: ChainlinkPythPriceAggregator;
    let chainlinkAggregator: IAggregatorV3Interface;
    let keeper: SignerWithAddress;

    utils.beforeAfterReset(beforeEach, afterEach);

    before(async () => {
      const ChainlinkPythPriceAggregator = await ethers.getContractFactory("ChainlinkPythPriceAggregator");
      chainlinkPythAggregator = await ChainlinkPythPriceAggregator.deploy(tokenToTest, pythAddress, oracleData);
      await chainlinkPythAggregator.deployed();

      chainlinkAggregator = await ethers.getContractAt(
        "IAggregatorV3Interface",
        oracleData.onchainOracle.oracleContract,
      );

      [keeper] = await ethers.getSigners();
    });

    it("should be able to return price nominated in USD", async () => {
      const { answer: tokenUsdPrice } = await chainlinkPythAggregator.latestRoundData();
      const { answer: chainlinkUsdPrice } = await chainlinkAggregator.latestRoundData();
      checkAlmostSame(tokenUsdPrice, chainlinkUsdPrice, 0.2);
    });

    it("should be able to return fresher Pyth price", async () => {
      const { answer: tokenUsdPriceBefore, updatedAt: oracleTimestampBefore } =
        await chainlinkPythAggregator.latestRoundData();

      await updatePythPriceFeed(pythAddress, oracleData.offchainOracle.priceId, keeper);

      const { answer: tokenUsdPriceAfter, updatedAt: oracleTimestampAfter } =
        await chainlinkPythAggregator.latestRoundData();

      expect(oracleTimestampAfter).gt(oracleTimestampBefore);
      expect(tokenUsdPriceAfter).not.eq(tokenUsdPriceBefore);
    });

    it("should be able to return valid min and max price", async () => {
      const { min: min, max: max } = await chainlinkPythAggregator.getTokenMinMaxPrice(true);

      const { answer: tokenUsdPrice } = await chainlinkPythAggregator.latestRoundData();

      expect(min).lt(tokenUsdPrice);
      expect(max).gt(tokenUsdPrice);
      expect(min.mul(105).div(100)).gt(tokenUsdPrice);
      expect(max.mul(100).div(105)).lt(tokenUsdPrice);

      await updatePythPriceFeed(pythAddress, oracleData.offchainOracle.priceId, keeper);
    });

    it("revert when price is stale", async () => {
      utils.increaseTime(86600);

      await expect(chainlinkPythAggregator.latestRoundData()).to.be.revertedWith("Onchain oracle price is stale");
    });
  });
};
