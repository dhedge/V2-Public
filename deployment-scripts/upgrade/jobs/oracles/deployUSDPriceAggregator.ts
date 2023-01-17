import { HardhatRuntimeEnvironment } from "hardhat/types";
import { Address } from "../../../types";
import { IAssetConfig, IUSDPriceAggregatorSpecificConfig, TAssetConfig, TOracleDeployer } from "./oracleTypes";

export const deployUSDPriceAggregator: TOracleDeployer = async (
  hre: HardhatRuntimeEnvironment,
  oracleConfig: TAssetConfig,
): Promise<Address> => {
  if (isUSDAggregator(oracleConfig)) {
    return Promise.resolve(oracleConfig.specificOracleConfig.USDPriceOracleAddress);
  } else {
    throw new Error("USDPriceAggregator config incorrect: " + oracleConfig.assetAddress);
  }
};

const isUSDAggregator = (
  oracleConfig: TAssetConfig,
): oracleConfig is IAssetConfig<"USDPriceAggregator", IUSDPriceAggregatorSpecificConfig> => {
  if (
    oracleConfig.oracleType != "USDPriceAggregator" ||
    !oracleConfig.specificOracleConfig ||
    !("USDPriceOracleAddress" in oracleConfig.specificOracleConfig)
  ) {
    return false;
  }
  return true;
};
