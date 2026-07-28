import { HardhatRuntimeEnvironment } from "hardhat/types";

import { TAssetConfig, IOndoAttestationAggregatorConfig } from "./oracleTypes";
import { tryVerify } from "../../../deploymentHelpers";
import { Address } from "../../../types";

const validateAssetConfig = (assetConfig: TAssetConfig): assetConfig is IOndoAttestationAggregatorConfig => {
  const requiredFields = ["ondoAttestationOracle"];

  if (
    assetConfig.oracleType !== "OndoAttestationAggregator" ||
    !requiredFields.every((field) => field in assetConfig.specificOracleConfig)
  ) {
    return false;
  }
  return true;
};

const deployOndoAttestationAggregatorJob = async (
  hre: HardhatRuntimeEnvironment,
  assetConfig: IOndoAttestationAggregatorConfig,
) => {
  const OndoAttestationAggregator = await hre.ethers.getContractFactory("OndoAttestationAggregator");

  console.log("Deploying OndoAttestationAggregator oracle...");

  const config = assetConfig.specificOracleConfig;

  const args: Parameters<typeof OndoAttestationAggregator.deploy> = [
    config.ondoAttestationOracle,
    assetConfig.assetAddress,
  ];

  const ondoAttestationAggregator = await OndoAttestationAggregator.deploy(...args);
  await ondoAttestationAggregator.deployed();

  await tryVerify(
    hre,
    ondoAttestationAggregator.address,
    "contracts/priceAggregators/OndoAttestationAggregator.sol:OndoAttestationAggregator",
    args,
  );

  return ondoAttestationAggregator.address;
};

export const deployOndoAttestationAggregator = async (
  hre: HardhatRuntimeEnvironment,
  assetConfig: TAssetConfig,
): Promise<Address> => {
  if (!validateAssetConfig(assetConfig)) {
    throw new Error(`${assetConfig.assetName} has not a valid config`);
  }

  const address = await deployOndoAttestationAggregatorJob(hre, assetConfig);
  return address;
};
