import { HardhatRuntimeEnvironment } from "hardhat/types";

import { TAssetConfig, IPythPriceAggregatorConfig } from "./oracleTypes";
import { tryVerify } from "../../../deploymentHelpers";
import { Address } from "../../../types";

const validateAssetConfig = (assetConfig: TAssetConfig): assetConfig is IPythPriceAggregatorConfig => {
  const requiredFields = ["maxAge", "pythOracleContract", "priceId"];

  if (
    assetConfig.oracleType !== "PythPriceAggregator" ||
    !requiredFields.every((field) => field in assetConfig.specificOracleConfig)
  ) {
    return false;
  }
  return true;
};

const deployPythPriceAggregatorJob = async (
  hre: HardhatRuntimeEnvironment,
  assetConfig: IPythPriceAggregatorConfig,
) => {
  const PythPriceAggregator = await hre.ethers.getContractFactory("PythPriceAggregator");

  console.log("Deploying PythPriceAggregator oracle...");

  const args: Parameters<typeof PythPriceAggregator.deploy> = [
    assetConfig.assetAddress,
    assetConfig.specificOracleConfig.pythOracleContract,
    {
      maxAge: assetConfig.specificOracleConfig.maxAge,
      minConfidenceRatio: 50, // 100/50 => +-2% price deviation acceptable,
      priceId: assetConfig.specificOracleConfig.priceId,
    },
  ];
  const pythPriceAggregator = await PythPriceAggregator.deploy(...args);
  await pythPriceAggregator.deployed();

  await tryVerify(
    hre,
    pythPriceAggregator.address,
    "contracts/priceAggregators/PythPriceAggregator.sol:PythPriceAggregator",
    args,
  );
  return pythPriceAggregator.address;
};

export const deployPythPriceAggregator = async (
  hre: HardhatRuntimeEnvironment,
  assetConfig: TAssetConfig,
): Promise<Address> => {
  if (!validateAssetConfig(assetConfig)) {
    throw new Error(`${assetConfig.assetName} has not a valid config`);
  }

  const address = await deployPythPriceAggregatorJob(hre, assetConfig);
  return address;
};
