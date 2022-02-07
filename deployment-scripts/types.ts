import { HardhatRuntimeEnvironment } from "hardhat/types";

export interface IUpgradeConfigProposeTx {
  execute: boolean;
  restartnonce: boolean;
}

export type IUpgradeConfig = IUpgradeConfigProposeTx & {
  oldTag: string;
  newTag: string;
};

export type IJob<T> = (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // This need to be typed but its a bit of work
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => Promise<T>;

// File Names
export interface IFileNames {
  versionsFileName: string;
  assetsFileName: string;
  governanceNamesFileName: string;
  contractGuardsFileName: string;
  assetGuardsFileName: string;

  balancerConfigFileName?: string;
  externalAssetFileName?: string;
}

export interface ExternalLogicContracts {
  dhedgeEasySwapperAddress?: string;

  synthetixProxyAddress?: string;
  synthetixAddressResolverAddress?: string;

  balancerV2VaultAddress?: string;
  sushiMiniChefV2Address?: string;
  balancerMerkleOrchardAddress?: string;
  aaveProtocolDataProviderAddress?: string;

  quickStakingRewardsFactoryAddress?: string;
  v2RouterAddresses?: string[]; //quickswapRouter, sushiswapV2Router etc etc
  quickLpUsdcWethStakingRewardsAddress?: string;
  aaveIncentivesControllerAddress?: string;
  aaveLendingPoolAddress?: string;
  oneInchV4RouterAddress?: string;

  // Token Addresses
  sushiTokenAddress?: string;
  wmaticTokenAddress?: string;
}

export interface IDhedgeInternal {
  // Dhedge
  protocolDaoAddress: string;
  protocolTreasuryAddress: string;
  proxyAdminAddress: string;
  implementationStorageAddress: "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";
}

export type IProposeTxProperties = IDhedgeInternal & {
  // Gnosis safe multicall/send address
  // https://github.com/gnosis/safe-deployments
  gnosisMultiSendAddress: string;
  gnosisApi: string;
};

// Addresses
export type IAddresses = IProposeTxProperties & ExternalLogicContracts;

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

export type Address = string;

export interface IContracts {
  Governance: Address;
  PoolFactoryProxy: Address;
  PoolFactory: Address;
  PoolLogicProxy: Address;
  PoolLogic: Address;
  PoolManagerLogicProxy: Address;
  PoolManagerLogic: Address;
  AssetHandlerProxy: Address;
  AssetHandler: Address;
  PoolPerformanceProxy: Address;
  PoolPerformance: Address;
  DynamicBonds?: Address;

  SynthetixGuard?: Address;
  ERC20Guard?: Address;
  USDPriceAggregator?: Address;
  OpenAssetGuard?: Address;
  UniswapV2RouterGuard?: Address;
  SushiMiniChefV2Guard?: Address;
  QuickStakingRewardsGuard?: Address;
  OneInchV4Guard?: Address;
  EasySwapperGuard?: Address;
  BalancerV2Guard?: Address;
  BalancerMerkleOrchardGuard?: Address;
  AaveLendingPoolGuard?: Address;
  AaveIncentivesControllerGuard?: Address;
  SushiLPAssetGuard?: Address;
  LendingEnabledAssetGuard?: Address;
  QuickLPAssetGuard?: Address;
  AaveLendingPoolAssetGuard?: Address;

  Assets?: { name: string; asset: Address; assetType: string | undefined; aggregator: Address | undefined }[];
}

export type IVersions = {
  [version: string]: {
    network: {
      chainId: number;
      name: string;
    };
    lastUpdated: string;
    contracts: IContracts;
  };
};

export interface ICSVAsset {
  AssetName: string;
  Address: Address;
  AssetType: string;
  ChainlinkPriceFeed?: string;
  AggregatorName?: string;
}
