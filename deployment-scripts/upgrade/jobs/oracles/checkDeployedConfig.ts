import { HardhatRuntimeEnvironment } from "hardhat/types";
import { Address } from "../../../types";
import { IAssetConfig, TAssetConfig, TOracleDeployer, IDhedgeDeployedAggregatorSpecificConfig } from "./oracleTypes";

export const checkDeployedConfig: TOracleDeployer = async (
  _: HardhatRuntimeEnvironment,
  _oracleConfig: TAssetConfig,
): Promise<Address> => {
  if (!checkConfig(_oracleConfig)) {
    throw new Error("DhedgeDeployedAggregator config incorrect");
  }
  return Promise.resolve(_oracleConfig.specificOracleConfig.alreadyDeployedOracleAddress);
};

const checkConfig = (
  oracleConfig: TAssetConfig,
): oracleConfig is IAssetConfig<"DhedgeDeployedAggregator", IDhedgeDeployedAggregatorSpecificConfig> => {
  if (
    oracleConfig.oracleType != "DhedgeDeployedAggregator" ||
    !oracleConfig.specificOracleConfig ||
    !("alreadyDeployedOracleAddress" in oracleConfig.specificOracleConfig)
  ) {
    return false;
  }
  return true;
};
