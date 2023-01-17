import { HardhatRuntimeEnvironment } from "hardhat/types";
import { tryVerify } from "../../../Helpers";
import { Address } from "../../../types";
import {
  IAssetConfig,
  IBalancerStablePoolAggregatorSpecificConfig,
  TAssetConfig,
  TOracleDeployer,
} from "./oracleTypes";

export const deployBalancerComposableStablePoolAggregator: TOracleDeployer = async (
  hre: HardhatRuntimeEnvironment,
  oracleConfig: TAssetConfig,
): Promise<Address> => {
  const { dhedgeFactoryProxy } = validateConfig(oracleConfig);
  const args: [Address, Address] = [dhedgeFactoryProxy, oracleConfig.assetAddress];
  const BalancerStablePoolAggregator = await hre.ethers.getContractFactory("BalancerComposableStablePoolAggregator");

  const balancerStablePoolAggregator = await BalancerStablePoolAggregator.deploy(...args);
  await balancerStablePoolAggregator.deployed();
  await balancerStablePoolAggregator.deployTransaction.wait(5);
  await tryVerify(
    hre,
    balancerStablePoolAggregator.address,
    "contracts/priceAggregators/BalancerComposableStablePoolAggregator.sol:BalancerComposableStablePoolAggregator",
    args,
  );
  return balancerStablePoolAggregator.address;
};

const isBalancerComposableStablePoolAggregator = (
  oracleConfig: TAssetConfig,
): oracleConfig is IAssetConfig<"BalancerStablePoolAggregator", IBalancerStablePoolAggregatorSpecificConfig> => {
  const requiredFields = ["dhedgeFactoryProxy"];
  const { specificOracleConfig } = oracleConfig;
  const isCorrectOracleType = oracleConfig.oracleType == "BalancerComposableStablePoolAggregator";
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
  if (!isBalancerComposableStablePoolAggregator(oracleConfig)) {
    throw new Error("MedianTWAPAggregator config incorrect: " + oracleConfig.assetAddress);
  }

  return specificOracleConfig as IBalancerStablePoolAggregatorSpecificConfig;
};
