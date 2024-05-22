import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx } from "../../deploymentHelpers";
import { Address, IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions, ContractGuardType } from "../../types";
import { balancerV2GaugeContractGuardJob } from "./contractGuards/balancerV2GaugeContractGuardJob";
import { synthetixFuturesMarketContractGuardJob } from "./contractGuards/synthetixFuturesMarketContractGuardJob";
import { velodromeGaugeContractGuardJob } from "./contractGuards/velodromeGaugeContractGuardJob";
import { arrakisLiquidityGaugeV4ContractGuardJob } from "./contractGuards/arrakisLiquidityGaugeV4ContractGuardJob";
import { addOrReplaceGuardInFile } from "./helpers";
import { TAssetConfig } from "./oracles/oracleTypes";
import { maiVaultContractGuardJob } from "./contractGuards/maiVaultContractGuardJob";
import { synthetixPerpsV2MarketContractGuardJob } from "./contractGuards/synthetixPerpsV2MarketContractGuardJob";
import { velodromeV2GaugeContractGuardJob } from "./contractGuards/velodromeV2GaugeContractGuardJob";
import { velodromePairContractGuardJob } from "./contractGuards/velodromePairContractGuardJob";
import { ramsesGaugeGuardJob } from "./contractGuards/ramsesGaugeGuardJob";
import { sonneFinanceCTokenContractGuardJob } from "./contractGuards/sonneFinanceCTokenContractGuardJob";

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
  guardName: "VelodromeGaugeContractGuard" | "VelodromeV2GaugeContractGuard",
  guardJob: typeof velodromeGaugeContractGuardJob | typeof velodromeV2GaugeContractGuardJob,
  voterAddressKey: "voter" | "voterV2",
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

const getExistingOrDeployedRamsesGuard = (guardName: ContractGuardType, deployer: IJob<void>) => {
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
      if (!guardAddress) {
        throw new Error(`No ${guardName} in versions`);
      }
    }
    if (!addresses.ramses?.voter) {
      throw new Error(`No Ramses voter configured in addresses`);
    }
    const voter = await hre.ethers.getContractAt("IRamsesVoter", addresses.ramses.voter);
    const associatedGauge = await voter.gauges(newAsset.assetAddress);
    if (associatedGauge == hre.ethers.constants.AddressZero) {
      throw new Error(`No ${newAsset.assetName} associated gauge`);
    }
    return { guardAddress, contractAddress: associatedGauge };
  };
};

const typeToContractGuardConfigurer: TContractGuardTypeToContractGuardConfigurer = {
  BalancerV2GaugeContractGuard: getExistingOrDeployGuard(
    "BalancerV2GaugeContractGuard",
    balancerV2GaugeContractGuardJob,
  ),
  VelodromeGaugeContractGuard: getExistingOrDeployedVelodromeGuard(
    "VelodromeGaugeContractGuard",
    velodromeGaugeContractGuardJob,
    "voter",
  ),
  SynthetixFuturesMarketContractGuard: getExistingOrDeployGuard(
    "SynthetixFuturesMarketContractGuard",
    synthetixFuturesMarketContractGuardJob,
  ),
  SynthetixPerpsV2MarketContractGuard: getExistingOrDeployGuard(
    "SynthetixPerpsV2MarketContractGuard",
    synthetixPerpsV2MarketContractGuardJob,
  ),
  ArrakisLiquidityGaugeV4ContractGuard: getExistingOrDeployGuard(
    "ArrakisLiquidityGaugeV4ContractGuard",
    arrakisLiquidityGaugeV4ContractGuardJob,
  ),
  MaiVaultContractGuard: getExistingOrDeployGuard("MaiVaultContractGuard", maiVaultContractGuardJob),
  VelodromeV2GaugeContractGuard: getExistingOrDeployedVelodromeGuard(
    "VelodromeV2GaugeContractGuard",
    velodromeV2GaugeContractGuardJob,
    "voterV2",
  ),
  VelodromePairContractGuard: getExistingOrDeployGuard("VelodromePairContractGuard", velodromePairContractGuardJob),
  RamsesGaugeContractGuard: getExistingOrDeployedRamsesGuard("RamsesGaugeContractGuard", ramsesGaugeGuardJob),
  SonneFinanceCTokenGuard: getExistingOrDeployGuard("SonneFinanceCTokenGuard", sonneFinanceCTokenContractGuardJob),
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
