import { HardhatRuntimeEnvironment } from "hardhat/types";

import { TAssetConfig, IFluidTokenPriceAggregatorConfig } from "./oracleTypes";
import { tryVerify } from "../../../deploymentHelpers";
import { Address } from "../../../types";

const validateAssetConfig = (assetConfig: TAssetConfig): assetConfig is IFluidTokenPriceAggregatorConfig => {
  const requiredFields = ["dhedgeFactoryProxy"];
  if (
    assetConfig.oracleType !== "FluidTokenPriceAggregator" ||
    !requiredFields.every((field) => field in assetConfig.specificOracleConfig)
  ) {
    return false;
  }
  return true;
};

const deployFluidTokenPriceAggregatorJob = async (
  hre: HardhatRuntimeEnvironment,
  assetConfig: IFluidTokenPriceAggregatorConfig,
) => {
  const FluidTokenPriceAggregator = await hre.ethers.getContractFactory("FluidTokenPriceAggregator");

  console.log("Deploying FluidTokenPriceAggregator oracle...");

  const args: [Address, Address] = [assetConfig.assetAddress, assetConfig.specificOracleConfig.dhedgeFactoryProxy];
  const fluidTokenPriceAggregator = await FluidTokenPriceAggregator.deploy(...args);
  await fluidTokenPriceAggregator.deployed();

  await tryVerify(
    hre,
    fluidTokenPriceAggregator.address,
    "contracts/priceAggregators/FluidTokenPriceAggregator.sol:FluidTokenPriceAggregator",
    args,
  );
  return fluidTokenPriceAggregator.address;
};

export const deployFluidTokenPriceAggregator = async (
  hre: HardhatRuntimeEnvironment,
  assetConfig: TAssetConfig,
): Promise<Address> => {
  if (!validateAssetConfig(assetConfig)) {
    throw new Error(`${assetConfig.assetName} has not a valid config`);
  }

  const address = await deployFluidTokenPriceAggregatorJob(hre, assetConfig);
  return address;
};
