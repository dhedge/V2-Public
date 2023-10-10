import { HardhatRuntimeEnvironment } from "hardhat/types";
import { tryVerify } from "../../../deploymentHelpers";
import { Address } from "../../../types";
import { TAssetConfig, TOracleDeployer, IMaticXPriceAggregatorSpecificConfig, IAssetConfig } from "./oracleTypes";

export const deployMaticXPriceAggregator: TOracleDeployer = async (
  hre: HardhatRuntimeEnvironment,
  oracleConfig: TAssetConfig,
): Promise<Address> => {
  const specificConfig = validateConfig(oracleConfig);

  return deployMaticXPriceAggregatorJob(specificConfig, hre);
};

const isMaticXPriceAggregator = (
  oracleConfig: TAssetConfig,
): oracleConfig is IAssetConfig<"MaticXPriceAggregator", IMaticXPriceAggregatorSpecificConfig> => {
  const requiredFields = ["dhedgeFactoryProxy"];
  const { specificOracleConfig } = oracleConfig;
  if (
    oracleConfig.oracleType != "MaticXPriceAggregator" ||
    !specificOracleConfig ||
    requiredFields.some((field) => !(field in oracleConfig.specificOracleConfig))
  ) {
    return false;
  }
  return true;
};

const validateConfig = (oracleConfig: TAssetConfig): IMaticXPriceAggregatorSpecificConfig => {
  const specificOracleConfig = oracleConfig.specificOracleConfig;
  if (!isMaticXPriceAggregator(oracleConfig)) {
    throw new Error("MaticXPriceAggregator config incorrect: " + oracleConfig.assetAddress);
  }

  return specificOracleConfig as IMaticXPriceAggregatorSpecificConfig;
};

export const deployMaticXPriceAggregatorJob = async (
  specificConfig: IMaticXPriceAggregatorSpecificConfig,
  hre: HardhatRuntimeEnvironment,
): Promise<Address> => {
  const MaticXPriceAggregator = await hre.ethers.getContractFactory("MaticXPriceAggregator");
  const maticXPriceAggregator = await MaticXPriceAggregator.deploy(
    specificConfig.Matic,
    specificConfig.MaticX,
    specificConfig.MaticXPool,
    specificConfig.dhedgeFactoryProxy,
  );
  await maticXPriceAggregator.deployed();

  await tryVerify(
    hre,
    maticXPriceAggregator.address,
    "contracts/priceAggregators/MaticXPriceAggregator.sol:MaticXPriceAggregator",
    [specificConfig.Matic, specificConfig.MaticX, specificConfig.MaticXPool, specificConfig.dhedgeFactoryProxy],
  );
  return maticXPriceAggregator.address;
};
