import { ethers } from "hardhat";
import { expect } from "chai";
import { IERC20Extended } from "../../../../types";
import { CTokenInterface } from "../../../../types/CTokenInterface";
import { SonneFinancePriceAggregator } from "../../../../types/SonneFinancePriceAggregator";
import { parseUnits } from "@ethersproject/units";

type SonneToken = {
  symbol: string;
  address: string;
  cToken: string;
};

interface ISonnePriceAggregatorTestParams {
  comptroller: string;
  tokens: SonneToken[];
}

export const runSonnePriceAggregatorTest = ({ comptroller, tokens }: ISonnePriceAggregatorTestParams) => {
  describe("SonnePriceAggregator Test", () => {
    let sonneFinancePriceAggregator: SonneFinancePriceAggregator;
    let cTokenContract: CTokenInterface;
    let mantissa: number;

    tokens.forEach((token) => {
      before(async () => {
        cTokenContract = <CTokenInterface>await ethers.getContractAt("CTokenInterface", token.cToken);
        const underlyingToken = <IERC20Extended>await ethers.getContractAt("IERC20Extended", token.address);
        const cToken = <IERC20Extended>await ethers.getContractAt("IERC20Extended", token.cToken);
        const underlyingTokenDecimals = await underlyingToken.decimals();
        const cTokenDecimals = await cToken.decimals();
        mantissa = underlyingTokenDecimals + 18 - cTokenDecimals;

        const SonneFinancePriceAggregator = await ethers.getContractFactory("SonneFinancePriceAggregator");
        sonneFinancePriceAggregator = await SonneFinancePriceAggregator.deploy(
          token.cToken,
          comptroller,
          parseUnits("0.02", mantissa.toString()),
        );
        await sonneFinancePriceAggregator.deployed();
      });

      it(`Should return the same exchange rate as the ${token.symbol} cToken contract`, async () => {
        const priceAggregatorExchangeRate = await sonneFinancePriceAggregator.exchangeRate();
        const cTokenExchangeRate = await cTokenContract.callStatic.exchangeRateCurrent();

        expect(cTokenExchangeRate).to.be.equal(priceAggregatorExchangeRate);
      });
    });
  });
};
