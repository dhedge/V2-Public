import { ethers } from "hardhat";
import { expect } from "chai";
import { units } from "../../../testHelpers";
import { ETHCrossAggregator, IAggregatorV3Interface } from "../../../../types";
import { utils } from "../../utils/utils";

interface ITestParams {
  tokenToTest: string;
  tokenEthPriceFeed: string;
  ethUsdPriceFeed: string;
}

export const runETHCrossAggregatorTest = ({ tokenToTest, tokenEthPriceFeed, ethUsdPriceFeed }: ITestParams) => {
  describe("ETHCrossAggregator Test", () => {
    let ethCrossAggregator: ETHCrossAggregator;
    let tokenEthAggregator: IAggregatorV3Interface;
    let ethUsdAggregator: IAggregatorV3Interface;

    utils.beforeAfterReset(beforeEach, afterEach);

    before(async () => {
      const ETHCrossAggregator = await ethers.getContractFactory("ETHCrossAggregator");
      ethCrossAggregator = await ETHCrossAggregator.deploy(tokenToTest, tokenEthPriceFeed, ethUsdPriceFeed);
      await ethCrossAggregator.deployed();

      tokenEthAggregator = await ethers.getContractAt("IAggregatorV3Interface", tokenEthPriceFeed);
      ethUsdAggregator = await ethers.getContractAt("IAggregatorV3Interface", ethUsdPriceFeed);
    });

    it("should be able to return price nominated in USD", async () => {
      const { answer: tokenEthPrice } = await tokenEthAggregator.latestRoundData();
      const { answer: ethUsdPrice } = await ethUsdAggregator.latestRoundData();
      const { answer: tokenUsdPrice } = await ethCrossAggregator.latestRoundData();

      console.log("Token/ETH price:", tokenEthPrice.toString());
      console.log("ETH/USD price:", ethUsdPrice.toString());
      console.log("Token/USD price:", tokenUsdPrice.toString());
      expect(tokenUsdPrice).to.equal(ethUsdPrice.mul(tokenEthPrice).div(units(1)));
    });
  });
};
