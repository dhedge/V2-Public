import { HardhatRuntimeEnvironment } from "hardhat/types";
import { tryVerify } from "../../../Helpers";
import { Address } from "../../../types";
import { IBalancerLpStablePoolAggregatorConfig, TAssetConfig, TOracleDeployer } from "./oracleTypes";

export const deployBalancerStablePoolAggregator: TOracleDeployer = async (
  hre: HardhatRuntimeEnvironment,
  oracleConfig: TAssetConfig,
): Promise<Address> => {
  const specificConfig = validateConfig(oracleConfig);
  return deployBalancerLpStablePoolAggregator(hre, specificConfig.dhedgeFactoryProxy, oracleConfig.assetAddress);
};

const validateConfig = (oracleConfig: TAssetConfig): IBalancerLpStablePoolAggregatorConfig => {
  const specificOracleConfig = oracleConfig.specificOracleConfig;
  throw new Error("Needs to be implemented");
  return specificOracleConfig as IBalancerLpStablePoolAggregatorConfig;
};

export const deployBalancerLpStablePoolAggregator = async (
  hre: HardhatRuntimeEnvironment,
  factory: string,
  pool: string,
): Promise<Address> => {
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
