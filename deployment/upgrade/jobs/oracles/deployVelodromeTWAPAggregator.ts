import { HardhatRuntimeEnvironment } from "hardhat/types";

import { TAssetConfig, IVelodromeTWAPAggregatorConfig, IVelodromeV2TWAPAggregatorConfig } from "./oracleTypes";
import { tryVerify } from "../../../deploymentHelpers";
import { Address } from "../../../types";

type IVelodromeTWAPAggregatorType = "VelodromeTWAPAggregator" | "VelodromeV2TWAPAggregator";
type IVelodromeTWAPAggregatorConfigs = IVelodromeTWAPAggregatorConfig | IVelodromeV2TWAPAggregatorConfig;

const validateAssetConfig = (
  oracleConfig: TAssetConfig,
  contractName: IVelodromeTWAPAggregatorType,
): oracleConfig is IVelodromeTWAPAggregatorConfigs => {
  const requiredFields = ["pair", "mainToken", "pairToken", "pairTokenUsdAggregator"];
  if (
    oracleConfig.oracleType !== contractName ||
    !requiredFields.every((field) => field in oracleConfig.specificOracleConfig)
  ) {
    return false;
  }
  return true;
};

const deployVelodromeTWAPAggregatorJob = async (
  hre: HardhatRuntimeEnvironment,
  assetConfig: IVelodromeTWAPAggregatorConfigs,
  contractName: IVelodromeTWAPAggregatorType,
) => {
  const VelodromeTWAPAggregator = await hre.ethers.getContractFactory(contractName);

  console.log(`Deploying ${contractName} oracle...`);

  const args: [Address, Address, Address, Address] = [
    assetConfig.specificOracleConfig.pair,
    assetConfig.specificOracleConfig.mainToken,
    assetConfig.specificOracleConfig.pairToken,
    assetConfig.specificOracleConfig.pairTokenUsdAggregator,
  ];
  const velodromeTWAPAggregator = await VelodromeTWAPAggregator.deploy(...args);
  await velodromeTWAPAggregator.deployed();

  await tryVerify(
    hre,
    velodromeTWAPAggregator.address,
    `contracts/priceAggregators/${contractName}.sol:${contractName}`,
    args,
  );
  return velodromeTWAPAggregator.address;
};

export const deployVelodromeTWAPAggregator = async (
  hre: HardhatRuntimeEnvironment,
  assetConfig: TAssetConfig,
  contractName: IVelodromeTWAPAggregatorType,
): Promise<Address> => {
  if (!validateAssetConfig(assetConfig, contractName)) {
    throw new Error(`${assetConfig.assetName} has not a valid ${contractName} config`);
  }

  const address = await deployVelodromeTWAPAggregatorJob(hre, assetConfig, contractName);
  return address;
};
