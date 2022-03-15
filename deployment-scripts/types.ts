import { HardhatRuntimeEnvironment } from "hardhat/types";
import { TAssetConfig } from "./upgrade/jobs/oracles/oracleTypes";

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
  uniswapV3RouterAddress?: Address;
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
  PoolPerformanceProxy: Address;
  PoolPerformance: Address;
  DynamicBondsProxy?: Address;
  DynamicBonds?: Address;
  ProxyAdmin?: Address;

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
  UniswapV3RouterGuard?: Address;

  // Asset Guards
  SushiLPAssetGuard?: Address;
  LendingEnabledAssetGuard?: Address;
  QuickLPAssetGuard?: Address;
  AaveLendingPoolAssetGuard?: Address;
  UniswapV3AssetGuard?: Address;

  DhedgeEasySwapper: Address;
  DhedgeSwapRouter: Address;

  Assets: TDeployedAsset[];
}

export type TDeployedAsset = TAssetConfig & { oracleAddress: string };

export interface IDeployedOracle {
  assetAddress: Address;
  oracleAddress: Address;
  oracleType: string;
}

export type OracleType =
  | "ChainlinkAggregator"
  | "DHedgePoolAggregator"
  | "USDPriceAggregator"
  | "UniV2LPAggregator"
  | "BalancerV2LPAggregator"
  | "SynthPriceAggregator"
  | "BalancerStablePoolAggregator"
  | "MedianTWAPAggregator"
  | "UniV3TWAPAggregator";

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
