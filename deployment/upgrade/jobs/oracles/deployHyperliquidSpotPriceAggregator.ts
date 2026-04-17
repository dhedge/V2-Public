import { HardhatRuntimeEnvironment } from "hardhat/types";
import { Address } from "../../../types";
import { tryVerify } from "../../../deploymentHelpers";
import {
  IAssetConfig,
  TAssetConfig,
  TOracleDeployer,
  IHyperliquidSpotPriceAggregatorSpecificConfig,
} from "./oracleTypes";

const validateConfig = (
  oracleConfig: TAssetConfig,
): oracleConfig is IAssetConfig<"HyperliquidSpotPriceAggregator", IHyperliquidSpotPriceAggregatorSpecificConfig> => {
  if (
    oracleConfig.oracleType != "HyperliquidSpotPriceAggregator" ||
    !oracleConfig.specificOracleConfig ||
    !("spotIndex" in oracleConfig.specificOracleConfig) ||
    !("usdcUsdFeed" in oracleConfig.specificOracleConfig)
  ) {
    return false;
  }
  return true;
};

export const deployHyperliquidSpotPriceAggregator: TOracleDeployer = async (
  hre: HardhatRuntimeEnvironment,
  oracleConfig: TAssetConfig,
): Promise<Address> => {
  if (!validateConfig(oracleConfig)) {
    throw new Error(`${oracleConfig.assetName} has not a valid HyperliquidSpotPriceAggregator config`);
  }

  const { spotIndex, usdcUsdFeed } = oracleConfig.specificOracleConfig;

  const HyperliquidSpotPriceAggregator = await hre.ethers.getContractFactory("HyperliquidSpotPriceAggregator");

  console.log("Deploying HyperliquidSpotPriceAggregator oracle...");

  const args: [number, Address] = [spotIndex, usdcUsdFeed];
  const aggregator = await HyperliquidSpotPriceAggregator.deploy(...args);
  await aggregator.deployed();

  await tryVerify(
    hre,
    aggregator.address,
    "contracts/priceAggregators/HyperliquidSpotPriceAggregator.sol:HyperliquidSpotPriceAggregator",
    args,
  );

  return aggregator.address;
};
