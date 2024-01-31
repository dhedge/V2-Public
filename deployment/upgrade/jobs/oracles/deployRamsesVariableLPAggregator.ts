import { HardhatRuntimeEnvironment } from "hardhat/types";

import { TAssetConfig, IRamsesLPVariableAggregatorConfig } from "./oracleTypes";
import { tryVerify } from "../../../deploymentHelpers";
import { Address } from "../../../types";

const validateAssetConfig = (assetConfig: TAssetConfig): assetConfig is IRamsesLPVariableAggregatorConfig => {
  const requiredFields = ["dhedgeFactoryProxy"];
  if (
    assetConfig.oracleType !== "RamsesVariableLPAggregator" ||
    !requiredFields.every((field) => field in assetConfig.specificOracleConfig)
  ) {
    return false;
  }
  return true;
};

const deployRamsesVariableLPAggregatorJob = async (
  hre: HardhatRuntimeEnvironment,
  assetConfig: IRamsesLPVariableAggregatorConfig,
) => {
  const RamsesVariableLPAggregator = await hre.ethers.getContractFactory("RamsesVariableLPAggregator");

  console.log("Deploying RamsesVariableLPAggregator oracle...");

  const args: [Address, Address] = [assetConfig.assetAddress, assetConfig.specificOracleConfig.dhedgeFactoryProxy];
  const ramsesVariableLPAggregator = await RamsesVariableLPAggregator.deploy(...args);
  await ramsesVariableLPAggregator.deployed();

  await tryVerify(
    hre,
    ramsesVariableLPAggregator.address,
    "contracts/priceAggregators/RamsesVariableLPAggregator.sol:RamsesVariableLPAggregator",
    args,
  );
  return ramsesVariableLPAggregator.address;
};

export const deployRamsesVariableLPAggregator = async (
  hre: HardhatRuntimeEnvironment,
  assetConfig: TAssetConfig,
): Promise<Address> => {
  if (!validateAssetConfig(assetConfig)) {
    throw new Error(`${assetConfig.assetName} has not a valid config`);
  }

  const address = await deployRamsesVariableLPAggregatorJob(hre, assetConfig);
  return address;
};
