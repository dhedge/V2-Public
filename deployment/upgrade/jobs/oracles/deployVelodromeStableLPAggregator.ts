import { HardhatRuntimeEnvironment } from "hardhat/types";
import { tryVerify } from "../../../deploymentHelpers";
import { Address } from "../../../types";
import { IAssetConfig, IVelodromeStableLPAggregatorSpecificConfig, TAssetConfig, TOracleDeployer } from "./oracleTypes";

export const deployVelodromeStableLPAggregator: TOracleDeployer = async (
  hre: HardhatRuntimeEnvironment,
  oracleConfig: TAssetConfig,
): Promise<Address> => {
  const { ethers } = hre;

  const specificOracleConfig: IVelodromeStableLPAggregatorSpecificConfig = validateConfig(oracleConfig);

  const VelodromeStableLPAggregator = await ethers.getContractFactory("VelodromeStableLPAggregator");
  const velodromeStableLPAggregator = await VelodromeStableLPAggregator.deploy(
    oracleConfig.assetAddress,
    specificOracleConfig.dhedgeFactoryProxy,
  );
  await velodromeStableLPAggregator.deployed();
  await velodromeStableLPAggregator.deployTransaction.wait(5);

  await tryVerify(
    hre,
    velodromeStableLPAggregator.address,
    "contracts/priceAggregators/VelodromeStableLPAggregator.sol:VelodromeStableLPAggregator",
    [oracleConfig.assetAddress, specificOracleConfig.dhedgeFactoryProxy],
  );

  return velodromeStableLPAggregator.address;
};

const isVelodromeStableLPAggregator = (
  oracleConfig: TAssetConfig,
): oracleConfig is IAssetConfig<"VelodromeStableLPAggregator", IVelodromeStableLPAggregatorSpecificConfig> => {
  const requiredFields = ["dhedgeFactoryProxy"];
  const { specificOracleConfig } = oracleConfig;
  if (
    oracleConfig.oracleType != "VelodromeStableLPAggregator" ||
    !specificOracleConfig ||
    requiredFields.some((field) => !(field in oracleConfig.specificOracleConfig))
  ) {
    return false;
  }
  return true;
};

const validateConfig = (oracleConfig: TAssetConfig): IVelodromeStableLPAggregatorSpecificConfig => {
  const specificOracleConfig = oracleConfig.specificOracleConfig;
  if (!isVelodromeStableLPAggregator(oracleConfig)) {
    throw new Error("VelodromeStableLPAggregator config incorrect: " + oracleConfig.assetAddress);
  }

  return specificOracleConfig as IVelodromeStableLPAggregatorSpecificConfig;
};
