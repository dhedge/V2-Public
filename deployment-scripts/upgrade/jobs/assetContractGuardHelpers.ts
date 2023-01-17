import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx } from "../../Helpers";
import { Address, IAddresses, IFileNames, IUpgradeConfig, IVersions } from "../../types";
import { balancerV2GaugeContractGuardJob } from "./contractGuards/balancerV2GaugeContractGuardJob";
import { futuresMarketContractGuardJob } from "./contractGuards/futuresMarketContractGuardJob";
import { velodromeGaugeContractGuardJob } from "./contractGuards/velodromeGaugeContractGuardJob";
import { arrakisLiquidityGaugeV4ContractGuardJob } from "./contractGuards/arrakisLiquidityGaugeV4ContractGuardJob";
import { addOrReplaceGuardInFile } from "./helpers";
import { TAssetConfig } from "./oracles/oracleTypes";

export type ContractGuardType =
  | "BalancerV2GaugeContractGuard"
  | "VelodromeGaugeContractGuard"
  | "FuturesMarketContractGuard"
  | "ArrakisLiquidityGaugeV4ContractGuard";

export type TContractGuardConfigurer = (
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

const typeToContractGuardConfigurer: TContractGuardTypeToContractGuardConfigurer = {
  BalancerV2GaugeContractGuard: async (
    config: IUpgradeConfig,
    hre: HardhatRuntimeEnvironment,
    versions: IVersions,
    filenames: IFileNames,
    addresses: IAddresses,
    newAsset: TAssetConfig,
  ) => {
    let guardAddress = versions[config.newTag].contracts.BalancerV2GaugeContractGuard;
    if (!guardAddress) {
      await balancerV2GaugeContractGuardJob(config, hre, versions, filenames, addresses);
      guardAddress = versions[config.newTag].contracts.BalancerV2GaugeContractGuard;
    }
    if (!guardAddress) {
      throw new Error("No BalancerV2GaugeContractGuard in versions");
    }
    return { guardAddress, contractAddress: newAsset.assetAddress };
  },
  VelodromeGaugeContractGuard: async (
    config: IUpgradeConfig,
    hre: HardhatRuntimeEnvironment,
    versions: IVersions,
    filenames: IFileNames,
    addresses: IAddresses,
    newAsset: TAssetConfig,
  ) => {
    let guardAddress = versions[config.newTag].contracts.VelodromeGaugeContractGuard;
    if (!guardAddress) {
      await velodromeGaugeContractGuardJob(config, hre, versions, filenames, addresses);
      guardAddress = versions[config.newTag].contracts.VelodromeGaugeContractGuard;
      if (!guardAddress) {
        throw new Error("No VelodromeGaugeContractGuard in versions");
      }
    }
    if (!addresses.velodrome?.voter) {
      throw new Error("No Velodrome Voter configured in addresses");
    }
    const voter = await hre.ethers.getContractAt("IVelodromeVoter", addresses.velodrome.voter);
    const associatedGauge = await voter.gauges(newAsset.assetAddress);
    if (associatedGauge == hre.ethers.constants.AddressZero) {
      throw new Error("No Velodrome associatedGauge");
    }
    return { guardAddress, contractAddress: associatedGauge };
  },
  FuturesMarketContractGuard: async (
    config: IUpgradeConfig,
    hre: HardhatRuntimeEnvironment,
    versions: IVersions,
    filenames: IFileNames,
    addresses: IAddresses,
    newAsset: TAssetConfig,
  ) => {
    let guardAddress = versions[config.newTag].contracts.FuturesMarketContractGuard;
    if (!guardAddress) {
      await futuresMarketContractGuardJob(config, hre, versions, filenames, addresses);
      guardAddress = versions[config.newTag].contracts.VelodromeGaugeContractGuard;
    }
    if (!guardAddress) {
      throw new Error("No FuturesMarketContractGuard in versions");
    }
    return { guardAddress, contractAddress: newAsset.assetAddress };
  },
  ArrakisLiquidityGaugeV4ContractGuard: async (
    config: IUpgradeConfig,
    hre: HardhatRuntimeEnvironment,
    versions: IVersions,
    filenames: IFileNames,
    addresses: IAddresses,
    newAsset: TAssetConfig,
  ) => {
    let guardAddress = versions[config.newTag].contracts.ArrakisLiquidityGaugeV4ContractGuard;
    if (!guardAddress) {
      await arrakisLiquidityGaugeV4ContractGuardJob(config, hre, versions, filenames, addresses);
      guardAddress = versions[config.newTag].contracts.ArrakisLiquidityGaugeV4ContractGuard;
    }
    if (!guardAddress) {
      throw new Error("No ArrakisLiquidityGaugeV4ContractGuard in versions");
    }
    return { guardAddress, contractAddress: newAsset.assetAddress };
  },
};

export const configureContractGuard = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
  newAsset: TAssetConfig,
) => {
  if (newAsset.specificContractGuardConfig?.contractGuard) {
    const contractGuardName = newAsset.specificContractGuardConfig.contractGuard;
    const contractGuardConfigurer = typeToContractGuardConfigurer[contractGuardName];
    if (!contractGuardConfigurer) {
      throw new Error("Missing contractGuardConfigurer for " + contractGuardName);
    }
    const contractGuardConfig = await contractGuardConfigurer(config, hre, versions, filenames, addresses, newAsset);
    await proposeContractGuardConfiguration(config, hre, versions, filenames, addresses, {
      ...contractGuardConfig,
      name: contractGuardName,
    });
  }
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
