import { HardhatRuntimeEnvironment } from "hardhat/types";

import { TAssetConfig, ISonneFinancePriceAggregatorConfig } from "./oracleTypes";
import { tryVerify } from "../../../deploymentHelpers";
import { Address } from "../../../types";
import { CErc20Interface, IERC20Extended } from "../../../../types";
import { parseUnits } from "ethers/lib/utils";
import { BigNumber } from "ethers";

const validateAssetConfig = (oracleConfig: TAssetConfig): oracleConfig is ISonneFinancePriceAggregatorConfig => {
  const requiredFields = ["comptroller", "initialExchangeRateMantissa"];
  if (
    oracleConfig.oracleType !== "SonneFinancePriceAggregator" ||
    !requiredFields.every((field) => field in oracleConfig.specificOracleConfig)
  ) {
    return false;
  }
  return true;
};

const deploySonneFinancePriceAggregatorJob = async (
  hre: HardhatRuntimeEnvironment,
  assetConfig: ISonneFinancePriceAggregatorConfig,
) => {
  const { ethers } = hre;
  const SonneFinancePriceAggregator = await hre.ethers.getContractFactory("SonneFinancePriceAggregator");

  const cTokenContract = <CErc20Interface>await ethers.getContractAt("CErc20Interface", assetConfig.assetAddress);
  const underlyingAddress = await cTokenContract.underlying();
  const underlyingToken = <IERC20Extended>await ethers.getContractAt("IERC20Extended", underlyingAddress);
  const cToken = <IERC20Extended>await ethers.getContractAt("IERC20Extended", assetConfig.assetAddress);
  const underlyingTokenDecimals = await underlyingToken.decimals();
  const cTokenDecimals = await cToken.decimals();

  // Calculate the mantissa for the initialExchangeRateMantissa.
  const mantissa = underlyingTokenDecimals + 18 - cTokenDecimals;

  const initialExchangeRateMantissa = parseUnits(
    assetConfig.specificOracleConfig.initialExchangeRateMantissa.toString(),
    mantissa.toString(),
  );

  console.log("Deploying SonneFinancePriceAggregator oracle...");

  const args: [Address, Address, BigNumber] = [
    assetConfig.assetAddress,
    assetConfig.specificOracleConfig.comptroller,
    initialExchangeRateMantissa,
  ];
  const sonneFinancePriceAggregator = await SonneFinancePriceAggregator.deploy(...args);
  await sonneFinancePriceAggregator.deployed();

  await tryVerify(
    hre,
    sonneFinancePriceAggregator.address,
    "contracts/priceAggregators/SonneFinancePriceAggregator.sol:SonneFinancePriceAggregator",
    args,
  );
  return sonneFinancePriceAggregator.address;
};

export const deploySonneFinancePriceAggregator = async (
  hre: HardhatRuntimeEnvironment,
  assetConfig: TAssetConfig,
): Promise<Address> => {
  if (!validateAssetConfig(assetConfig)) {
    throw new Error(`${assetConfig.assetName} has not a valid SonneFinancePriceAggregator config`);
  }

  const address = await deploySonneFinancePriceAggregatorJob(hre, assetConfig);
  return address;
};
