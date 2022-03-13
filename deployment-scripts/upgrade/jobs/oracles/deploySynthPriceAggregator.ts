import { HardhatRuntimeEnvironment } from "hardhat/types";
import { tryVerify } from "../../../Helpers";
import { Address } from "../../../types";
import { ISynthPriceAggregatorConfig, TAssetConfig, TOracleDeployer } from "./oracleTypes";

export const deploySynthPriceAggregator: TOracleDeployer = async (
  hre: HardhatRuntimeEnvironment,
  oracleConfig: TAssetConfig,
): Promise<Address> => {
  const { ethers } = hre;

  const specificOracleConfig: ISynthPriceAggregatorConfig = validateConfig(oracleConfig);

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

const validateConfig = (oracleConfig: TAssetConfig): ISynthPriceAggregatorConfig => {
  const specificOracleConfig = oracleConfig.specificOracleConfig;

  throw new Error("Needs to be implemented");

  return specificOracleConfig as ISynthPriceAggregatorConfig;
};
