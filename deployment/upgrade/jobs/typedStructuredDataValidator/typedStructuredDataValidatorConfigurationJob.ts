import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";

// Enum must match StructuredDataSupported in TypedStructuredDataValidator.sol
enum StructuredDataSupported {
  ODOS_LIMIT_ORDER,
  COW_SWAP_ORDER,
}

export const typedStructuredDataValidatorConfigurationJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  _filenames: IFileNames,
  addresses: IAddresses,
) => {
  console.log("Will configure TypedStructuredDataValidator");

  const typedStructuredDataValidatorProxy = versions[config.newTag].contracts.TypedStructuredDataValidatorProxy;

  if (!typedStructuredDataValidatorProxy) {
    return console.warn("TypedStructuredDataValidatorProxy missing... skipping.");
  }

  await configureCowSwapOrder(hre, config, versions, addresses, typedStructuredDataValidatorProxy);
};

const configureCowSwapOrder = async (
  hre: HardhatRuntimeEnvironment,
  config: IUpgradeConfig,
  _: IVersions,
  addresses: IAddresses,
  typedStructuredDataValidatorProxy: string,
) => {
  const cowSwapConfig = addresses.typedStructuredDataValidator?.cowSwapOrder;

  if (!cowSwapConfig) {
    return console.warn("CowSwap order config missing... skipping.");
  }

  if (config.execute) {
    const ethers = hre.ethers;

    const cowSwapValidationConfig = ethers.utils.defaultAbiCoder.encode(
      ["address", "uint256"],
      [cowSwapConfig.gpv2Settlement, cowSwapConfig.maxUnfavorableDeviationBps],
    );
    console.log("Encoded CowSwapValidationConfig:", cowSwapValidationConfig);

    const TypedStructuredDataValidator = await hre.artifacts.readArtifact("TypedStructuredDataValidator");
    const setValidationConfigTxData = new ethers.utils.Interface(TypedStructuredDataValidator.abi).encodeFunctionData(
      "setValidationConfig",
      [StructuredDataSupported.COW_SWAP_ORDER, cowSwapValidationConfig],
    );

    await proposeTx(
      typedStructuredDataValidatorProxy,
      setValidationConfigTxData,
      "Set CowSwap Order validation config",
      config,
      addresses,
    );
  }
};
