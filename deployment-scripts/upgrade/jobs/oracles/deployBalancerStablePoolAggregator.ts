import { HardhatRuntimeEnvironment } from "hardhat/types";
import { tryVerify } from "../../../Helpers";
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
  const specificConfig = validateConfig(oracleConfig);
  return deploy(hre, specificConfig.dhedgeFactoryProxy, oracleConfig.assetAddress);
};

const isBalancerStablePoolAggregator = (
  oracleConfig: TAssetConfig,
): oracleConfig is IAssetConfig<"BalancerStablePoolAggregator", IBalancerStablePoolAggregatorSpecificConfig> => {
  const requiredFields = ["dhedgeFactoryProxy"];
  const { specificOracleConfig } = oracleConfig;
  if (
    oracleConfig.oracleType != "BalancerStablePoolAggregator" ||
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

const deploy = async (hre: HardhatRuntimeEnvironment, factory: string, pool: string): Promise<Address> => {
  const BalancerStablePoolAggregator = await hre.ethers.getContractFactory("BalancerStablePoolAggregator");

  const balancerStablePoolAggregator = await BalancerStablePoolAggregator.deploy(factory, pool);
  await balancerStablePoolAggregator.deployed();
  await tryVerify(
    hre,
    balancerStablePoolAggregator.address,
    "contracts/priceAggregators/BalancerStablePoolAggregator.sol:BalancerStablePoolAggregator",
    [factory, pool],
  );
  return balancerStablePoolAggregator.address;
};
