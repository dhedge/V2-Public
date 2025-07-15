import { HardhatRuntimeEnvironment } from "hardhat/types";

import { TAssetConfig, IPendlePTPriceAggregatorConfig } from "./oracleTypes";
import { tryVerify } from "../../../deploymentHelpers";
import { Address } from "../../../types";

const validateAssetConfig = (assetConfig: TAssetConfig): assetConfig is IPendlePTPriceAggregatorConfig => {
  const requiredFields = ["syEquivalentYieldToken", "pendleChainlinkOracle", "dhedgeFactoryProxy"];
  if (
    assetConfig.oracleType !== "PendlePTPriceAggregator" ||
    !requiredFields.every((field) => field in assetConfig.specificOracleConfig)
  ) {
    return false;
  }
  return true;
};

const deployPendlePTPriceAggregatorJob = async (
  hre: HardhatRuntimeEnvironment,
  assetConfig: IPendlePTPriceAggregatorConfig,
) => {
  const PendlePTPriceAggregator = await hre.ethers.getContractFactory("PendlePTPriceAggregator");

  console.log("Deploying PendlePTPriceAggregator oracle...");

  const args: [Address, Address, Address] = [
    assetConfig.specificOracleConfig.syEquivalentYieldToken,
    assetConfig.specificOracleConfig.pendleChainlinkOracle,
    assetConfig.specificOracleConfig.dhedgeFactoryProxy,
  ];

  const pendlePTPriceAggregator = await PendlePTPriceAggregator.deploy(...args);
  await pendlePTPriceAggregator.deployed();

  await tryVerify(
    hre,
    pendlePTPriceAggregator.address,
    "contracts/priceAggregators/PendlePTPriceAggregator.sol:PendlePTPriceAggregator",
    args,
  );
  return pendlePTPriceAggregator.address;
};

export const deployPendlePTPriceAggregator = async (
  hre: HardhatRuntimeEnvironment,
  assetConfig: TAssetConfig,
): Promise<Address> => {
  if (!validateAssetConfig(assetConfig)) {
    throw new Error(`${assetConfig.assetName} has not a valid config`);
  }

  const address = await deployPendlePTPriceAggregatorJob(hre, assetConfig);
  return address;
};
