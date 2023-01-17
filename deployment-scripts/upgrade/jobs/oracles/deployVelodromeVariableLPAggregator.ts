import { HardhatRuntimeEnvironment } from "hardhat/types";
import { tryVerify } from "../../../Helpers";
import { Address } from "../../../types";
import {
  IAssetConfig,
  IVelodromeVariableLPAggregatorSpecificConfig,
  TAssetConfig,
  TOracleDeployer,
} from "./oracleTypes";

export const deployVelodromeVariableLPAggregator: TOracleDeployer = async (
  hre: HardhatRuntimeEnvironment,
  oracleConfig: TAssetConfig,
): Promise<Address> => {
  const { ethers } = hre;

  const specificOracleConfig: IVelodromeVariableLPAggregatorSpecificConfig = validateConfig(oracleConfig);

  const VelodromeVariableLPAggregator = await ethers.getContractFactory("VelodromeVariableLPAggregator");
  const velodromeVariableLPAggregator = await VelodromeVariableLPAggregator.deploy(
    oracleConfig.assetAddress,
    specificOracleConfig.dhedgeFactoryProxy,
  );

  await velodromeVariableLPAggregator.deployed();
  await velodromeVariableLPAggregator.deployTransaction.wait(5);

  await tryVerify(
    hre,
    velodromeVariableLPAggregator.address,
    "contracts/priceAggregators/VelodromeVariableLPAggregator.sol:VelodromeVariableLPAggregator",
    [oracleConfig.assetAddress, specificOracleConfig.dhedgeFactoryProxy],
  );
  return velodromeVariableLPAggregator.address;
};

const isVelodromeVariableLPAggregator = (
  oracleConfig: TAssetConfig,
): oracleConfig is IAssetConfig<"VelodromeVariableLPAggregator", IVelodromeVariableLPAggregatorSpecificConfig> => {
  const requiredFields = ["dhedgeFactoryProxy"];
  const { specificOracleConfig } = oracleConfig;
  if (
    oracleConfig.oracleType != "VelodromeVariableLPAggregator" ||
    !specificOracleConfig ||
    requiredFields.some((field) => !(field in oracleConfig.specificOracleConfig))
  ) {
    return false;
  }
  return true;
};

const validateConfig = (oracleConfig: TAssetConfig): IVelodromeVariableLPAggregatorSpecificConfig => {
  const specificOracleConfig = oracleConfig.specificOracleConfig;
  if (!isVelodromeVariableLPAggregator(oracleConfig)) {
    throw new Error("VelodromeVariableLPAggregator config incorrect: " + oracleConfig.assetAddress);
  }

  return specificOracleConfig as IVelodromeVariableLPAggregatorSpecificConfig;
};
