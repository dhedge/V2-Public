import { HardhatRuntimeEnvironment } from "hardhat/types";
import { tryVerify } from "../../../deploymentHelpers";
import { Address } from "../../../types";
import {
  IAssetConfig,
  IBalancerStablePoolAggregatorSpecificConfig,
  TAssetConfig,
  TOracleDeployer,
} from "./oracleTypes";

export const deployBalancerStablePoolAggregator: TOracleDeployer = async (
  hre: HardhatRuntimeEnvironment,
  oracleConfig: TAssetConfig,
): Promise<Address> => {
  const { dhedgeFactoryProxy } = validateConfig(oracleConfig);
  const BalancerStablePoolAggregator = await hre.ethers.getContractFactory("BalancerStablePoolAggregator");
  const args: [Address, Address] = [dhedgeFactoryProxy, oracleConfig.assetAddress];
  const balancerStablePoolAggregator = await BalancerStablePoolAggregator.deploy(...args);
  await balancerStablePoolAggregator.deployed();
  await tryVerify(
    hre,
    balancerStablePoolAggregator.address,
    "contracts/priceAggregators/BalancerStablePoolAggregator.sol:BalancerStablePoolAggregator",
    args,
  );
  return balancerStablePoolAggregator.address;
};

const isBalancerStablePoolAggregator = (
  oracleConfig: TAssetConfig,
): oracleConfig is IAssetConfig<"BalancerStablePoolAggregator", IBalancerStablePoolAggregatorSpecificConfig> => {
  const requiredFields = ["dhedgeFactoryProxy"];
  const { specificOracleConfig } = oracleConfig;
  const isCorrectOracleType = oracleConfig.oracleType == "BalancerStablePoolAggregator";
  if (
    !isCorrectOracleType ||
    !specificOracleConfig ||
    requiredFields.some((field) => !(field in oracleConfig.specificOracleConfig))
  ) {
    return false;
  }
  return true;
};

const validateConfig = (oracleConfig: TAssetConfig): IBalancerStablePoolAggregatorSpecificConfig => {
  const specificOracleConfig = oracleConfig.specificOracleConfig;
  if (!isBalancerStablePoolAggregator(oracleConfig)) {
    throw new Error("MedianTWAPAggregator config incorrect: " + oracleConfig.assetAddress);
  }

  return specificOracleConfig as IBalancerStablePoolAggregatorSpecificConfig;
};
