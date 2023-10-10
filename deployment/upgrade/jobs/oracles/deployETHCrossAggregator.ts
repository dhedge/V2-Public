import { HardhatRuntimeEnvironment } from "hardhat/types";

import { TAssetConfig, IETHCrossAggregatorConfig } from "./oracleTypes";
import { tryVerify } from "../../../deploymentHelpers";
import { Address } from "../../../types";

const validateAssetConfig = (oracleConfig: TAssetConfig): oracleConfig is IETHCrossAggregatorConfig => {
  if (
    oracleConfig.oracleType !== "ETHCrossAggregator" ||
    !oracleConfig.specificOracleConfig.assetToEthChainlinkOracleAddress ||
    !oracleConfig.specificOracleConfig.ethToUsdChainlinkOracleAddress
  ) {
    return false;
  }
  return true;
};

const deployETHCrossAggregatorJob = async (hre: HardhatRuntimeEnvironment, assetConfig: IETHCrossAggregatorConfig) => {
  const ETHCrossAggregatorFactory = await hre.ethers.getContractFactory("ETHCrossAggregator");
  const args: [Address, Address, Address] = [
    assetConfig.assetAddress,
    assetConfig.specificOracleConfig.assetToEthChainlinkOracleAddress,
    assetConfig.specificOracleConfig.ethToUsdChainlinkOracleAddress,
  ];
  const ethCrossAggregator = await ETHCrossAggregatorFactory.deploy(...args);
  await ethCrossAggregator.deployed();
  await tryVerify(
    hre,
    ethCrossAggregator.address,
    "contracts/priceAggregators/ETHCrossAggregator.sol:ETHCrossAggregator",
    args,
  );
  return ethCrossAggregator.address;
};

export const deployETHCrossAggregator = async (
  hre: HardhatRuntimeEnvironment,
  assetConfig: TAssetConfig,
): Promise<Address> => {
  if (!validateAssetConfig(assetConfig)) {
    throw new Error(`${assetConfig.assetName} has not a valid ETHCrossAggregator config`);
  }
  const address = await deployETHCrossAggregatorJob(hre, assetConfig);
  return address;
};
