import { HardhatRuntimeEnvironment } from "hardhat/types";

import { TAssetConfig, IERC4626PriceAggregatorConfig } from "./oracleTypes";
import { tryVerify } from "../../../deploymentHelpers";
import { Address } from "../../../types";

const validateAssetConfig = (assetConfig: TAssetConfig): assetConfig is IERC4626PriceAggregatorConfig => {
  const requiredFields = ["dhedgeFactoryProxy"];
  if (
    assetConfig.oracleType !== "ERC4626PriceAggregator" ||
    !requiredFields.every((field) => field in assetConfig.specificOracleConfig)
  ) {
    return false;
  }
  return true;
};

export const deployERC4626PriceAggregatorJob = async (
  hre: HardhatRuntimeEnvironment,
  assetAddress: Address,
  dhedgeFactoryProxy: Address,
): Promise<Address> => {
  const factory = await hre.ethers.getContractAt("IPoolFactory", dhedgeFactoryProxy);
  const assetHandler = await factory.getAssetHandler();

  const ERC4626PriceAggregator = await hre.ethers.getContractFactory("ERC4626PriceAggregator");

  console.log("Deploying ERC4626PriceAggregator oracle...");

  const args: [Address, Address] = [assetAddress, assetHandler];

  const erc4626PriceAggregator = await ERC4626PriceAggregator.deploy(...args);
  await erc4626PriceAggregator.deployed();

  await tryVerify(
    hre,
    erc4626PriceAggregator.address,
    "contracts/priceAggregators/ERC4626PriceAggregator.sol:ERC4626PriceAggregator",
    args,
  );
  return erc4626PriceAggregator.address;
};

export const deployERC4626PriceAggregator = async (
  hre: HardhatRuntimeEnvironment,
  assetConfig: TAssetConfig,
): Promise<Address> => {
  if (!validateAssetConfig(assetConfig)) {
    throw new Error(`${assetConfig.assetName} has not a valid config`);
  }

  const address = await deployERC4626PriceAggregatorJob(
    hre,
    assetConfig.assetAddress,
    assetConfig.specificOracleConfig.dhedgeFactoryProxy,
  );
  return address;
};
