import { HardhatRuntimeEnvironment } from "hardhat/types";
import { tryVerify } from "../../../Helpers";
import { Address } from "../../../types";
import { IAssetConfig, IUniV2LPAggregatorSpecificConfig, TAssetConfig, TOracleDeployer } from "./oracleTypes";

export const deployUniV2LPAggregator: TOracleDeployer = async (
  hre: HardhatRuntimeEnvironment,
  oracleConfig: TAssetConfig,
): Promise<Address> => {
  const { ethers } = hre;

  const specificOracleConfig: IUniV2LPAggregatorSpecificConfig = validateConfig(oracleConfig);

  const SushiLPAggregator = await ethers.getContractFactory("UniV2LPAggregator");
  const sushiLPAggregator = await SushiLPAggregator.deploy(
    oracleConfig.assetAddress,
    specificOracleConfig.dhedgeFactoryProxy,
  );

  await tryVerify(
    hre,
    sushiLPAggregator.address,
    "contracts/priceAggregators/UniV2LPAggregator.sol:UniV2LPAggregator",
    [oracleConfig.assetAddress, specificOracleConfig.dhedgeFactoryProxy],
  );

  await sushiLPAggregator.deployed();
  return sushiLPAggregator.address;
};

const isUniV2LPAggregator = (
  oracleConfig: TAssetConfig,
): oracleConfig is IAssetConfig<"UniV2LPAggregator", IUniV2LPAggregatorSpecificConfig> => {
  const requiredFields = ["dhedgeFactoryProxy"];
  const { specificOracleConfig } = oracleConfig;
  if (
    oracleConfig.oracleType != "UniV2LPAggregator" ||
    !specificOracleConfig ||
    requiredFields.some((field) => !(field in oracleConfig.specificOracleConfig))
  ) {
    return false;
  }
  return true;
};

const validateConfig = (oracleConfig: TAssetConfig): IUniV2LPAggregatorSpecificConfig => {
  const specificOracleConfig = oracleConfig.specificOracleConfig;
  if (!isUniV2LPAggregator(oracleConfig)) {
    throw new Error("UniV2LPAggregator config incorrect: " + oracleConfig.assetAddress);
  }

  return specificOracleConfig as IUniV2LPAggregatorSpecificConfig;
};
