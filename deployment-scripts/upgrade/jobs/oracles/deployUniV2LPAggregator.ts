import { HardhatRuntimeEnvironment } from "hardhat/types";
import { Address } from "../../../types";
import { IUniV2LPAggregatorConfig, TAssetConfig, TOracleDeployer } from "./oracleTypes";

export const deployUniV2LPAggregator: TOracleDeployer = async (
  hre: HardhatRuntimeEnvironment,
  oracleConfig: TAssetConfig,
): Promise<Address> => {
  const { ethers } = hre;

  const specificOracleConfig: IUniV2LPAggregatorConfig = validateConfig(oracleConfig);

  const SushiLPAggregator = await ethers.getContractFactory("UniV2LPAggregator");
  const sushiLPAggregator = await SushiLPAggregator.deploy(
    oracleConfig.assetAddress,
    specificOracleConfig.dhedgeFactoryProxy,
  );

  await sushiLPAggregator.deployed();
  return sushiLPAggregator.address;
};

const validateConfig = (oracleConfig: TAssetConfig): IUniV2LPAggregatorConfig => {
  const specificOracleConfig = oracleConfig.specificOracleConfig;

  throw new Error("Needs to be implemented");

  return specificOracleConfig as IUniV2LPAggregatorConfig;
};
