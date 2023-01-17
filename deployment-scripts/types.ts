import { HardhatRuntimeEnvironment } from "hardhat/types";
import { TAssetConfig } from "./upgrade/jobs/oracles/oracleTypes";
import { BigNumber } from "ethers";

export interface IUpgradeConfigProposeTx {
  execute: boolean;
  restartnonce: boolean;
  useNonce: number;
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
  synthetixProxyAddress?: Address;
  synthetixAddressResolverAddress?: Address;

  balancerV2VaultAddress?: Address;
  sushiMiniChefV2Address?: Address;
  balancerMerkleOrchardAddress?: Address;

  quickStakingRewardsFactoryAddress?: Address;
  v2RouterAddresses?: string[]; //quickswapRouter, sushiswapV2Router etc etc

  swapRouterCurvePools?: string[];
  quickLpUsdcWethStakingRewardsAddress?: Address;
  aaveIncentivesControllerAddress?: Address;
  oneInchV4RouterAddress?: Address;
  oneInchV5RouterAddress?: Address;

  velodrome?: {
    router: Address;
    voter: Address;
  };

  uniV3: {
    uniswapV3RouterAddress: Address;
    uniswapV3FactoryAddress: Address;
    uniSwapV3NonfungiblePositionManagerAddress?: Address;
  };

  aaveV2?: {
    aaveProtocolDataProviderAddress: Address;
    aaveLendingPoolAddress: Address;
  };

  aaveV3?: {
    aaveProtocolDataProviderAddress: Address;
    aaveLendingPoolAddress: Address;
    aaveIncentivesControllerAddress: Address;
  };

  arrakisV1?: {
    arrakisV1RouterStakingAddress: Address;
  };

  lyra?: {
    dhedgeLyraWrapper?: string;
    optionMarketWrapper: string;
    optionMarketViewer: string;
    lyraRegistry: string;
  };

  // Token Addresses
  sushiTokenAddress?: Address;
  wmaticTokenAddress?: Address;

  torosEasySwapperAllowedPools: Address[];

  assets: {
    nativeAssetWrapper: string;
    weth: string;
    usdc: string;
    dai: string;
    susd?: string;
    dht: string;
  };

  assetType5Router?: string;
  assetType2Router?: string;

  stakingV2Pools: { pool: string; cap: BigNumber }[];

  rewardDistribution?: {
    token: string;
    amountPerSecond: number;
  };
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
  gnosisMultiSendAddress?: string;
  gnosisApi?: string;
};

// Addresses
export type IAddresses = IProposeTxProperties & ExternalLogicContracts;

type RecordNumberString = Record<string, number | string>;
export interface IDeployedAssetGuard extends RecordNumberString {
  assetType: number;
  guardName: string;
  guardAddress: string;
  description: string;
}

export interface IDeployedContractGuard extends RecordNumberString {
  contractAddress: string;
  guardName: string;
  guardAddress: string;
  description: string;
}

export interface INotSureGuard {
  name: string;
  destination: string;
}

export type Address = string; // TODO: Could probably harden this type. Maybe Hardhat supports it?

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
  DhedgeStakingV2NFTJson?: Address;
  DhedgeStakingV2Proxy?: Address;
  DhedgeStakingV2?: Address;
  DynamicBondsProxy?: Address;
  DynamicBonds?: Address;
  ProxyAdmin?: Address;
  DhedgeNftTrackerStorageProxy: Address;
  DhedgeNftTrackerStorage: Address;
  RewardDistribution?: Address;

  // Contract Guards
  SynthetixGuard?: Address;
  USDPriceAggregator?: Address;
  UniswapV2RouterGuard?: Address;
  VelodromeRouterGuard?: Address;
  SushiMiniChefV2Guard?: Address;
  QuickStakingRewardsGuard?: Address;
  OneInchV4Guard?: Address;
  OneInchV5Guard?: Address;
  EasySwapperGuard?: Address;
  BalancerV2Guard?: Address;
  BalancerMerkleOrchardGuard?: Address;
  AaveLendingPoolGuardV2?: Address;
  AaveLendingPoolGuardV3?: Address;
  AaveIncentivesControllerGuard?: Address;
  AaveIncentivesControllerV3Guard?: Address;
  UniswapV3NonfungiblePositionGuard?: Address;
  UniswapV3RouterGuard?: Address;
  ArrakisV1RouterStakingGuard?: Address;
  ArrakisLiquidityGaugeV4ContractGuard?: Address;
  BalancerV2GaugeContractGuard?: Address;
  VelodromeGaugeContractGuard?: Address;
  DhedgeOptionMarketWrapperForLyra?: Address;
  LyraOptionMarketWrapperContractGuard?: Address;
  ERC721ContractGuard?: Address;
  FuturesMarketContractGuard?: Address;

  // Asset Guards
  OpenAssetGuard: Address;
  ERC20Guard?: Address;
  SushiLPAssetGuard?: Address;
  LendingEnabledAssetGuard?: Address;
  SynthetixLendingEnabledAssetGuard?: Address;
  QuickLPAssetGuard?: Address;
  AaveLendingPoolAssetGuardV2?: Address;
  AaveLendingPoolAssetGuardV3?: Address;
  UniswapV3AssetGuard?: Address;
  ArrakisLiquidityGaugeV4AssetGuard?: Address;
  BalancerV2GaugeAssetGuard?: Address;
  VelodromeLPAssetGuard?: Address;
  LyraOptionMarketWrapperAssetGuard?: Address;
  FuturesMarketAssetGuard?: Address;

  DhedgeEasySwapperProxy: Address;
  DhedgeEasySwapper: Address;
  DhedgeSuperSwapper: Address;
  DhedgeUniV3V2Router: Address;
  DhedgeVeloV2Router: Address;

  Assets: TDeployedAsset[];
  RemovedAssets: TDeployedAsset[];
}

export type TDeployedAsset = TAssetConfig & { oracleAddress: string };

export interface IDeployedOracle {
  assetAddress: Address;
  oracleAddress: Address;
  oracleType: string;
}

export type OracleType =
  | "DhedgeDeployedAggregator"
  | "ChainlinkAggregator"
  | "DHedgePoolAggregator"
  | "USDPriceAggregator"
  | "UniV2LPAggregator"
  | "BalancerV2LPAggregator"
  | "SynthPriceAggregator"
  | "BalancerStablePoolAggregator"
  | "BalancerComposableStablePoolAggregator"
  | "MedianTWAPAggregator"
  | "UniV3TWAPAggregator"
  | "DQUICKPriceAggregator"
  | "VelodromeTWAPAggregator"
  | "VelodromeStableLPAggregator"
  | "VelodromeVariableLPAggregator"
  | "MaticXPriceAggregator";

export type ContractGuardType =
  | "BalancerV2GaugeContractGuard"
  | "VelodromeGaugeContractGuard"
  | "FuturesMarketContractGuard";

export type IVersion = {
  network: {
    chainId: number;
    name: string;
  };
  lastUpdated: string;
  contracts: IContracts;
};

export type IVersions = {
  [version: string]: IVersion;
};
