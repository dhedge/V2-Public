import { HardhatRuntimeEnvironment } from "hardhat/types";
import { tryVerify } from "../../../Helpers";
import { Address } from "../../../types";
import { IAssetConfig, ISynthPriceAggregatorSpecificConfig, TAssetConfig, TOracleDeployer } from "./oracleTypes";

export const deploySynthPriceAggregator: TOracleDeployer = async (
  hre: HardhatRuntimeEnvironment,
  oracleConfig: TAssetConfig,
): Promise<Address> => {
  const { ethers } = hre;

  const specificOracleConfig: ISynthPriceAggregatorSpecificConfig = validateConfig(oracleConfig);

  const SynthPriceAggregator = await ethers.getContractFactory("SynthPriceAggregator");
  const synthPriceAggregator = await SynthPriceAggregator.deploy(
    specificOracleConfig.susdPriceAggregator,
    specificOracleConfig.tokenUSDPriceAggregator,
  );

  synthPriceAggregator.deployed();
  await tryVerify(
    hre,
    synthPriceAggregator.address,
    "contracts/priceAggregators/SynthPriceAggregator.sol:SynthPriceAggregator",
    [specificOracleConfig.susdPriceAggregator, specificOracleConfig.tokenUSDPriceAggregator],
  );
  return synthPriceAggregator.address;
};

const isSynthPriceAggregator = (
  oracleConfig: TAssetConfig,
): oracleConfig is IAssetConfig<"SynthPriceAggregator", ISynthPriceAggregatorSpecificConfig> => {
  const requiredFields = ["susdPriceAggregator", "tokenUSDPriceAggregator"];
  const { specificOracleConfig } = oracleConfig;
  if (
    oracleConfig.oracleType != "SynthPriceAggregator" ||
    !specificOracleConfig ||
    requiredFields.some((field) => !(field in oracleConfig.specificOracleConfig))
  ) {
    return false;
  }
  return true;
};

const validateConfig = (oracleConfig: TAssetConfig): ISynthPriceAggregatorSpecificConfig => {
  const specificOracleConfig = oracleConfig.specificOracleConfig;
  if (!isSynthPriceAggregator(oracleConfig)) {
    throw new Error("SynthPriceAggregator config incorrect: " + oracleConfig.assetAddress);
  }

  return specificOracleConfig as ISynthPriceAggregatorSpecificConfig;
};
