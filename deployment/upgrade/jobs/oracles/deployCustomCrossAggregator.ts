import { HardhatRuntimeEnvironment } from "hardhat/types";

import { TAssetConfig, ICustomCrossAggregatorConfig } from "./oracleTypes";
import { tryVerify } from "../../../deploymentHelpers";
import { Address } from "../../../types";

const validateAssetConfig = (assetConfig: TAssetConfig): assetConfig is ICustomCrossAggregatorConfig => {
  const requiredFields = ["tokenToTokenAggregator", "tokenToUsdAggregator"];
  if (
    assetConfig.oracleType !== "CustomCrossAggregator" ||
    !requiredFields.every((field) => field in assetConfig.specificOracleConfig)
  ) {
    return false;
  }
  return true;
};

const deployCustomCrossAggregatorJob = async (
  hre: HardhatRuntimeEnvironment,
  assetConfig: ICustomCrossAggregatorConfig,
) => {
  const CustomCrossAggregator = await hre.ethers.getContractFactory("CustomCrossAggregator");

  console.log("Deploying CustomCrossAggregator oracle...");

  const args: [Address, Address, Address] = [
    assetConfig.assetAddress,
    assetConfig.specificOracleConfig.tokenToTokenAggregator,
    assetConfig.specificOracleConfig.tokenToUsdAggregator,
  ];
  const customCrossAggregator = await CustomCrossAggregator.deploy(...args);
  await customCrossAggregator.deployed();

  await tryVerify(
    hre,
    customCrossAggregator.address,
    "contracts/priceAggregators/CustomCrossAggregator.sol:CustomCrossAggregator",
    args,
  );

  return customCrossAggregator.address;
};

export const deployCustomCrossAggregator = async (
  hre: HardhatRuntimeEnvironment,
  assetConfig: TAssetConfig,
): Promise<Address> => {
  if (!validateAssetConfig(assetConfig)) {
    throw new Error(`${assetConfig.assetName} has not a valid config`);
  }

  const address = await deployCustomCrossAggregatorJob(hre, assetConfig);
  return address;
};
