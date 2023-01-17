import { HardhatRuntimeEnvironment } from "hardhat/types";
import { Address } from "../../../types";
import { IAssetConfig, TAssetConfig, TOracleDeployer, IChainlinkAggregatorSpecificConfig } from "./oracleTypes";

export const checkChainlinkConfig: TOracleDeployer = async (
  _: HardhatRuntimeEnvironment,
  _oracleConfig: TAssetConfig,
): Promise<Address> => {
  if (!isChainlink(_oracleConfig)) {
    throw new Error("ChainlinkAggregator incorrect");
  }
  return Promise.resolve(_oracleConfig.specificOracleConfig.chainlinkOracleAddress);
};

const isChainlink = (
  oracleConfig: TAssetConfig,
): oracleConfig is IAssetConfig<"ChainlinkAggregator", IChainlinkAggregatorSpecificConfig> => {
  if (
    oracleConfig.oracleType != "ChainlinkAggregator" ||
    !oracleConfig.specificOracleConfig ||
    !("chainlinkOracleAddress" in oracleConfig.specificOracleConfig)
  ) {
    return false;
  }
  return true;
};
