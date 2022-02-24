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
  dhedgeEasySwapperAddress?: Address;

  synthetixProxyAddress?: Address;
  synthetixAddressResolverAddress?: Address;

  balancerV2VaultAddress?: Address;
  sushiMiniChefV2Address?: Address;
  balancerMerkleOrchardAddress?: Address;
  aaveProtocolDataProviderAddress?: Address;

  quickStakingRewardsFactoryAddress?: Address;
  v2RouterAddresses?: string[]; //quickswapRouter, sushiswapV2Router etc etc
  swapRouterCurvePools?: string[];
  quickLpUsdcWethStakingRewardsAddress?: Address;
  aaveIncentivesControllerAddress?: Address;
  aaveLendingPoolAddress?: Address;
  oneInchV4RouterAddress?: Address;

  uniSwapV3NonfungiblePositionManagerAddress?: Address;

  // Token Addresses
  sushiTokenAddress?: Address;
  wmaticTokenAddress?: Address;
}

export interface sUSDUniV3TWAPAggregatorProperties {
  // For sUSDUniV3TWAPAggregator
  sUSDAddress?: Address;
  sUSDDaiUniV3PoolAddress?: Address;
  daiChainlinkoracleAddress?: Address;
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
export type IAddresses = IProposeTxProperties & ExternalLogicContracts & sUSDUniV3TWAPAggregatorProperties;

export interface IDeployedAssetGuard {
  assetType: number;
  guardName: string;
  guardAddress: string;
  description: string;
}

export interface IDeployedContractGuard {
  ContractAddress: string;
  guardName: string;
  guardAddress: string;
  description: string;
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
  DynamicBondsProxy?: Address;
  DynamicBonds?: Address;

  // Contract Guards
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
  UniswapV3NonfungiblePositionGuard?: Address;

  // Asset Guards
  SushiLPAssetGuard?: Address;
  LendingEnabledAssetGuard?: Address;
  QuickLPAssetGuard?: Address;
  AaveLendingPoolAssetGuard?: Address;
  UniswapV3AssetGuard?: Address;

  // Oracles
  Oracles?: { assetAddress: Address; oracleAddress: Address; oracleName: string }[];

  DhedgeEasySwapper: Address;
  DhedgeSwapRouter: Address;

  Assets?: ICSVAsset[];
}

type OracleName =
  | "DHedgePoolAggregator"
  | "USDPriceAggregator"
  | "DeployedOracle"
  | "UniV2LPAggregator"
  | "BalancerV2LPAggregator";

export interface ICSVAsset {
  assetType: number;
  oracleName: OracleName;
  oracleAddress: Address;
  assetAddress: Address;
  assetName: string;
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
