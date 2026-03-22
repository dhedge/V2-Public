import { HardhatRuntimeEnvironment } from "hardhat/types";

import { TAssetConfig, IChainlinkAggregatorWrapperConfig } from "./oracleTypes";
import { tryVerify } from "../../../deploymentHelpers";
import { Address } from "../../../types";

const validateAssetConfig = (assetConfig: TAssetConfig): assetConfig is IChainlinkAggregatorWrapperConfig => {
  const requiredFields = ["chainlinkOracleAddress"];

  if (
    assetConfig.oracleType !== "ChainlinkAggregatorWrapper" ||
    !requiredFields.every((field) => field in assetConfig.specificOracleConfig)
  ) {
    return false;
  }
  return true;
};

const deployChainlinkAggregatorWrapperJob = async (
  hre: HardhatRuntimeEnvironment,
  assetConfig: IChainlinkAggregatorWrapperConfig,
) => {
  const ChainlinkAggregatorWrapper = await hre.ethers.getContractFactory("ChainlinkAggregatorWrapper");

  console.log("Deploying ChainlinkAggregatorWrapper oracle...");

  const args: Parameters<typeof ChainlinkAggregatorWrapper.deploy> = [
    assetConfig.specificOracleConfig.chainlinkOracleAddress,
  ];

  const chainlinkAggregatorWrapper = await ChainlinkAggregatorWrapper.deploy(...args);
  await chainlinkAggregatorWrapper.deployed();

  await tryVerify(
    hre,
    chainlinkAggregatorWrapper.address,
    "contracts/priceAggregators/ChainlinkAggregatorWrapper.sol:ChainlinkAggregatorWrapper",
    args,
  );
  return chainlinkAggregatorWrapper.address;
};

export const deployChainlinkAggregatorWrapper = async (
  hre: HardhatRuntimeEnvironment,
  assetConfig: TAssetConfig,
): Promise<Address> => {
  if (!validateAssetConfig(assetConfig)) {
    throw new Error(`${assetConfig.assetName} has not a valid config`);
  }

  const address = await deployChainlinkAggregatorWrapperJob(hre, assetConfig);
  return address;
};
