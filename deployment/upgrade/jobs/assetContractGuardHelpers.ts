import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx } from "../../deploymentHelpers";
import { Address, IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../types";
import { ContractGuardType } from "./oracles/oracleTypes";
import { addOrReplaceGuardInFile } from "./helpers";
import { TAssetConfig } from "./oracles/oracleTypes";
import { velodromeV2GaugeContractGuardJob } from "./contractGuards/velodromeV2GaugeContractGuardJob";
import { velodromePairContractGuardJob } from "./contractGuards/velodromePairContractGuardJob";
import { compoundV3CometContractGuardJob } from "./contractGuards/compoundV3CometContractGuardJob";
import { fluidTokenContractGuardJob } from "./contractGuards/fluidTokenContractGuardJob";

type TContractGuardConfigurer = (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
  newAsset: TAssetConfig,
) => Promise<{ contractAddress: Address; guardAddress: Address }>;

type TContractGuardTypeToContractGuardConfigurer = {
  [K in ContractGuardType]: TContractGuardConfigurer;
};

const getExistingOrDeployGuard = (guardName: ContractGuardType, deployer: IJob<void>) => {
  return async (
    config: IUpgradeConfig,
    hre: HardhatRuntimeEnvironment,
    versions: IVersions,
    filenames: IFileNames,
    addresses: IAddresses,
    newAsset: TAssetConfig,
  ) => {
    let guardAddress = versions[config.newTag].contracts[guardName];
    if (!guardAddress) {
      await deployer(config, hre, versions, filenames, addresses);
      guardAddress = versions[config.newTag].contracts[guardName];
    }
    if (!guardAddress) {
      throw new Error(`No ${guardName} in versions`);
    }
    return { guardAddress, contractAddress: newAsset.assetAddress };
  };
};

const getExistingOrDeployedVelodromeGuard = (
  guardName: "VelodromeV2GaugeContractGuard",
  guardJob: typeof velodromeV2GaugeContractGuardJob,
  voterAddressKey: "voterV2",
) => {
  return async (
    config: IUpgradeConfig,
    hre: HardhatRuntimeEnvironment,
    versions: IVersions,
    filenames: IFileNames,
    addresses: IAddresses,
    newAsset: TAssetConfig,
  ) => {
    let guardAddress = versions[config.newTag].contracts[guardName];
    if (!guardAddress) {
      await guardJob(config, hre, versions, filenames, addresses);
      guardAddress = versions[config.newTag].contracts[guardName];
      if (!guardAddress) {
        throw new Error(`No ${guardName} in versions`);
      }
    }
    const voterAddress = addresses.velodrome?.[voterAddressKey];
    if (!voterAddress) {
      throw new Error(`No Velodrome ${voterAddressKey} configured in addresses`);
    }
    const voter = await hre.ethers.getContractAt("IVelodromeVoter", voterAddress);
    const associatedGauge = await voter.gauges(newAsset.assetAddress);
    if (associatedGauge == hre.ethers.constants.AddressZero) {
      throw new Error("No Velodrome associatedGauge");
    }
    return { guardAddress, contractAddress: associatedGauge };
  };
};

const typeToContractGuardConfigurer: TContractGuardTypeToContractGuardConfigurer = {
  VelodromeV2GaugeContractGuard: getExistingOrDeployedVelodromeGuard(
    "VelodromeV2GaugeContractGuard",
    velodromeV2GaugeContractGuardJob,
    "voterV2",
  ),
  VelodromePairContractGuard: getExistingOrDeployGuard("VelodromePairContractGuard", velodromePairContractGuardJob),
  CompoundV3CometContractGuard: getExistingOrDeployGuard(
    "CompoundV3CometContractGuard",
    compoundV3CometContractGuardJob,
  ),
  FluidTokenContractGuard: getExistingOrDeployGuard("FluidTokenContractGuard", fluidTokenContractGuardJob),
};

export const configureContractGuard = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
  newAsset: TAssetConfig,
  contractGuardName: ContractGuardType,
) => {
  const contractGuardConfigurer = typeToContractGuardConfigurer[contractGuardName];
  if (!contractGuardConfigurer) {
    throw new Error("Missing contractGuardConfigurer for " + contractGuardName);
  }
  const contractGuardConfig = await contractGuardConfigurer(config, hre, versions, filenames, addresses, newAsset);
  await proposeContractGuardConfiguration(config, hre, versions, filenames, addresses, {
    ...contractGuardConfig,
    name: contractGuardName,
  });
};

export const proposeContractGuardConfiguration = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
  guardInfo: { contractAddress: Address; guardAddress: Address; name: string },
) => {
  const { contractAddress, guardAddress, name } = guardInfo;
  const ethers = hre.ethers;
  const governance = await ethers.getContractAt("Governance", versions[config.oldTag].contracts.Governance);
  const guardAddressSet = await governance.contractGuards(contractAddress);
  if (guardAddressSet.toLowerCase() === guardAddress.toLowerCase()) {
    return console.warn(`Guard ${guardAddress} already set for ${contractAddress}`);
  }
  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);
  const setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [contractAddress, guardAddress]);

  await proposeTx(
    versions[config.oldTag].contracts.Governance,
    setContractGuardABI,
    `setContractGuard for ${name}`,
    config,
    addresses,
  );

  const deployedGuard = {
    contractAddress,
    guardName: `${name}`,
    guardAddress: guardAddress,
    description: `${name}`,
  };
  await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
};
