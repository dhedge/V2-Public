import { HardhatRuntimeEnvironment } from "hardhat/types";

import { TAssetConfig, IFlatMoneyUNITPriceAggregatorConfig } from "./oracleTypes";
import { tryVerify } from "../../../deploymentHelpers";
import { Address } from "../../../types";

const validateAssetConfig = (assetConfig: TAssetConfig): assetConfig is IFlatMoneyUNITPriceAggregatorConfig => {
  const requiredFields = ["flatMoneyViewerAddress"];
  if (
    assetConfig.oracleType !== "FlatMoneyUNITPriceAggregator" ||
    !requiredFields.every((field) => field in assetConfig.specificOracleConfig)
  ) {
    return false;
  }
  return true;
};

const deployFlatMoneyUNITPriceAggregatorJob = async (
  hre: HardhatRuntimeEnvironment,
  assetConfig: IFlatMoneyUNITPriceAggregatorConfig,
) => {
  const FlatMoneyUNITPriceAggregator = await hre.ethers.getContractFactory("FlatMoneyUNITPriceAggregator");

  console.log("Deploying FlatMoneyUNITPriceAggregator oracle...");

  const args: [Address] = [assetConfig.specificOracleConfig.flatMoneyViewerAddress];
  const flatMoneyUNITPriceAggregator = await FlatMoneyUNITPriceAggregator.deploy(...args);
  await flatMoneyUNITPriceAggregator.deployed();

  await tryVerify(
    hre,
    flatMoneyUNITPriceAggregator.address,
    "contracts/priceAggregators/FlatMoneyUNITPriceAggregator.sol:FlatMoneyUNITPriceAggregator",
    args,
  );
  return flatMoneyUNITPriceAggregator.address;
};

export const deployFlatMoneyUNITPriceAggregator = async (
  hre: HardhatRuntimeEnvironment,
  assetConfig: TAssetConfig,
): Promise<Address> => {
  if (!validateAssetConfig(assetConfig)) {
    throw new Error(`${assetConfig.assetName} has not a valid config`);
  }

  const address = await deployFlatMoneyUNITPriceAggregatorJob(hre, assetConfig);
  return address;
};
