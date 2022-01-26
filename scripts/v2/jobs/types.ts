import { HardhatRuntimeEnvironment } from "hardhat/types";

export interface IUpgradeConfig {
  execute: boolean;
  restartnonce: boolean;
  oldTag: string;
  newTag: string;
}

export type IJob<T> = (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // This need to be typed but its a bit of work
  versions: any,
  filenames: IFileNames,
  addresses: IAddresses,
) => Promise<T>;

// File Names
export interface IFileNames {
  balancerConfigFileName?: string;
  assetsFileName: string;
  governanceNamesFileName: string;
  stagingAssetGuardFileName?: string;
  prodAssetGuardFileName?: string;
  stagingContractGuardFileName?: string;
  prodContractGuardFileName?: string;
  stagingGovernanceNamesFileName?: string;
  prodGovernanceNamesFileName?: string;
  stagingExternalAssetFileName?: string;
  prodExternalAssetFileName?: string;
}

// Addresses
export interface IAddresses {
  // Dhedge
  protocolDaoAddress: string;
  proxyAdminAddress: string;
  implementationStorageAddress: string;
  dhedgeEasySwapperAddress?: string;

  // External Logic Contracts
  balancerV2VaultAddress?: string;
  sushiMiniChefV2Address?: string;
  balancerMerkleOrchardAddress?: string;
  aaveProtocolDataProviderAddress?: string;

  quickStakingRewardsFactoryAddress?: string;
  v2RouterAddresses: string[]; //quickswapRouter, sushiswapV2Router etc etc
  quickLpUsdcWethStakingRewardsAddress?: string;
  aaveIncentivesControllerAddress?: string;
  aaveLendingPoolAddress?: string;
  oneInchV4RouterAddress?: string;

  // Token Addresses
  sushiTokenAddress?: string;
  wmaticTokenAddress?: string;
}

export interface IDeployedAssetGuard {
  AssetType: number;
  GuardName: string;
  GuardAddress: string;
  Description: string;
}

export interface IDeployedContractGuard {
  ContractAddress: string;
  GuardName: string;
  GuardAddress: string;
  Description: string;
}

export interface INotSureGuard {
  Name: string;
  Destination: string;
}
