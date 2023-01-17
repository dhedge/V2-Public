import { HardhatRuntimeEnvironment } from "hardhat/types";
import { tryVerify } from "../../../Helpers";
import { Address } from "../../../types";
import { TAssetConfig, TOracleDeployer, IDQUICKPriceAggregatorSpecificConfig, IAssetConfig } from "./oracleTypes";

export const deployDQUICKPriceAggregator: TOracleDeployer = async (
  hre: HardhatRuntimeEnvironment,
  oracleConfig: TAssetConfig,
): Promise<Address> => {
  const specificConfig = validateConfig(oracleConfig);

  return deployDQUICKPriceAggregatorJob(specificConfig, oracleConfig.assetAddress, hre);
};

const isDQUICKPriceAggregator = (
  oracleConfig: TAssetConfig,
): oracleConfig is IAssetConfig<"DQUICKPriceAggregator", IDQUICKPriceAggregatorSpecificConfig> => {
  const requiredFields = ["dhedgeFactoryProxy"];
  const { specificOracleConfig } = oracleConfig;
  if (
    oracleConfig.oracleType != "DQUICKPriceAggregator" ||
    !specificOracleConfig ||
    requiredFields.some((field) => !(field in oracleConfig.specificOracleConfig))
  ) {
    return false;
  }
  return true;
};

const validateConfig = (oracleConfig: TAssetConfig): IDQUICKPriceAggregatorSpecificConfig => {
  const specificOracleConfig = oracleConfig.specificOracleConfig;
  if (!isDQUICKPriceAggregator(oracleConfig)) {
    throw new Error("DQUICKPriceAggregator config incorrect: " + oracleConfig.assetAddress);
  }

  return specificOracleConfig as IDQUICKPriceAggregatorSpecificConfig;
};

export const deployDQUICKPriceAggregatorJob = async (
  specificConfig: IDQUICKPriceAggregatorSpecificConfig,
  pool: string,
  hre: HardhatRuntimeEnvironment,
): Promise<Address> => {
  const DQUICKPriceAggregator = await hre.ethers.getContractFactory("DQUICKPriceAggregator");
  const priceAggregator = await DQUICKPriceAggregator.deploy(
    specificConfig.dQUICK,
    specificConfig.QUICK,
    specificConfig.dhedgeFactoryProxy,
  );
  await priceAggregator.deployed();

  await tryVerify(
    hre,
    priceAggregator.address,
    "contracts/priceAggregators/dQUICKPriceAggregator.sol:DQUICKPriceAggregator",
    [specificConfig.QUICK, specificConfig.dQUICK, specificConfig.dhedgeFactoryProxy],
  );
  return priceAggregator.address;
};
