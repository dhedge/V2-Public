import { HardhatRuntimeEnvironment } from "hardhat/types";
import { TAssetConfig } from "./upgrade/jobs/oracles/oracleTypes";
import { BigNumber, BigNumberish } from "ethers";
import { AllowedMarketStruct } from "../types/SynthetixV3SpotMarketContractGuard";
import { VaultSettingStruct, WeeklyWindowsStruct } from "../types/SynthetixV3ContractGuard";
import { RewardAssetSettingStruct } from "../types/RewardAssetGuard";
import { PoolSettingStruct, VirtualTokenOracleSettingStruct } from "../types/GmxExchangeRouterContractGuard";
import { CustomSlippageStruct } from "../types/SynthetixPerpsV2MarketAssetGuard";
import { CrossChainBridgeStruct } from "../types/AcrossContractGuard";

export interface IUpgradeConfigProposeTx {
  execute: boolean;
  restartnonce: boolean;
  useNonce: number;
  chainId: number;
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
  governanceNamesFileName?: string;
  contractGuardsFileName: string;
  assetGuardsFileName: string;
  // This file is an entry point for guards deprecation and is picked by a script. Copy here guards for deprecation.
  deprecatedContractGuardsFileName?: string;
  externalAssetFileName?: string;
}

interface IEasySwapperConfig {
  customLockupAllowedPools: Address[];
  feeByPassManagers: Address[];
  feeNumerator: 10;
  feeDenominator: 10000;
}

interface IEasySwapperV2Config {
  customCooldownDepositsWhitelist: Address[];
}

interface IDeploymentsConfig {
  synthetixProxyAddress?: Address;

  balancerV2VaultAddress?: Address;
  balancerMerkleOrchardAddress?: Address;

  sushiMiniChefV2Address?: Address;

  v2RouterAddresses: Address[];

  quickStakingRewardsFactoryAddress?: Address;
  quickLpUsdcWethStakingRewardsAddress?: Address;
  quickswap?: {
    uniV2Factory: Address;
  };

  oneInchV4RouterAddress?: Address;
  oneInchV5RouterAddress?: Address;
  oneInchV6RouterAddress?: Address;

  velodrome?: {
    router?: Address;
    voter?: Address;
    routerV2: Address;
    voterV2?: Address;
    factoryV2: Address;
  };

  velodromeCL?: {
    nonfungiblePositionManager: Address;
    nonfungiblePositionManagerOld?: Address;
    factory: Address;
    enabledGauges: Address[];
    voter: Address;
  };

  stargate?: {
    router: Address;
    staking: Address;
  };

  uniV2: {
    factory: Address;
  };

  uniV3: {
    uniswapV3RouterAddress: Address;
    uniswapV3FactoryAddress: Address;
    uniSwapV3NonfungiblePositionManagerAddress?: Address;
  };

  aaveV2?: {
    aaveProtocolDataProviderAddress: Address;
    aaveLendingPoolAddress: Address;
    aaveIncentivesControllerAddress: Address;
  };

  aaveV3?: {
    aaveLendingPoolAddress: Address;
    aaveIncentivesControllerAddress?: Address;
  };

  aaveMigrationHelper?: {
    migrationHelperAddress: Address;
    dHedgeVaultsWhitelist: Address[];
    aaveV3DebtTokensWhitelist: Address[];
  };

  perpsV2?: {
    addressResolver: Address;
    whitelistedPools: Address[];
    withdrawSlippageSettings: CustomSlippageStruct[];
  };

  arrakisV1?: {
    arrakisV1RouterStakingAddress: Address;
  };

  lyra?: {
    dhedgeLyraWrapper?: Address;
    lyraRegistry: Address;
  };

  assets: {
    nativeAssetWrapper: Address;
    weth: Address;
    usdc?: Address;
    dai?: Address;
    susd?: Address;
    dht?: Address;
  };

  stakingV2?: {
    dhtCap: BigNumber;
    emissionsRate: number;
    whitelistedPools: { pool: Address; cap: BigNumber }[];
  };

  rewardDistribution?: {
    token: Address;
    amountPerSecond: BigNumberish;
    whitelistedPools: string[];
  }[];

  easySwapperConfig?: IEasySwapperConfig;

  superSwapper: {
    routeHints: { asset: Address; intermediary: Address }[];
  };

  synthRedeemer?: Address;

  zeroExExchangeProxy?: Address;

  synthetixV3?: {
    core: Address;
    dHedgeVaultsWhitelist: VaultSettingStruct[];
    spotMarket: Address;
    perpsMarket?: Address;
    perpsWithdrawAsset?: Address; // for SynthetixV3PerpsAssetGuard
    allowedMarkets: AllowedMarketStruct[];
    // Weekdays are 1-7, 1 being Monday and 7 being Sunday. Hours are 0-23
    windows: WeeklyWindowsStruct;
    withdrawalLimit: {
      usdValue: BigNumber;
      percent: BigNumber;
    };
  };

  poolTokenSwapper?: {
    manager: Address;
    assets: {
      asset: Address;
      assetEnabled: boolean;
    }[];
    pools: {
      pool: Address;
      poolSwapFee: number;
      poolEnabled: boolean;
    }[];
    swapWhitelist: {
      sender: Address;
      status: boolean;
    }[];
  };

  ramses?: {
    voter: Address;
    router: Address;
    xRam: Address;
  };

  ramsesCL?: {
    nonfungiblePositionManager: Address;
    voter: Address;
  };

  sonneFinance?: {
    dHedgeVaultsWhitelist: Address[];
    comptroller: Address;
  };

  flatMoney?: {
    delayedOrder?: Address;
    perpMarketWhitelistedVaults?: {
      poolLogic: Address;
      withdrawalAsset: Address;
    }[];
    swapper: Address;
  };

  rewardAssetSetting?: RewardAssetSettingStruct[];

  compoundV3?: {
    rewards: Address;
  };

  slippageAccumulator: {
    decayTime: number;
    maxCumulativeSlippage: number;
  };

  easySwapperV2: IEasySwapperV2Config;

  gmx?: {
    feeReceiver: Address;
    dataStore: Address;
    reader: Address;
    referralStorage: Address;
    exchangeRouter: Address;
    approvalRouter: Address;
    dHedgeVaultsWhitelist: PoolSettingStruct[];
    virtualTokenResolver: VirtualTokenOracleSettingStruct[];
  };

  angleProtocol?: {
    distributor: Address;
    rewardTokenSupported: Address;
  };

  poolLimitOrderManager: {
    defaultSlippageTolerance: number;
    settlementToken: Address;
    authorizedKeeperAddresses: Address[];
  };

  pancakeswap?: {
    nonfungiblePositionManager: Address;
    masterChefV3: Address;
  };

  across?: {
    spokePool: Address;
    approvedDestinations: CrossChainBridgeStruct[];
  };

  sky?: {
    psm3: Address;
  };

  flatMoneyOptions?: {
    orderAnnouncementModule: Address;
    orderExecutionModule: Address;
    flatcoinVault: Address;
  };

  odosV2RouterAddress?: Address;

  flatMoneyV2?: {
    orderAnnouncementModule: Address;
    orderExecutionModule: Address;
    whitelistedVaults: {
      poolLogic: Address;
      withdrawalAsset: Address;
    }[];
  };

  pendle?: {
    pendleRouterV4: Address;
    marketFactoryV3: Address;
    knownMarkets: Address[];
    yieldContractFactory: Address;
    staticRouter: Address;
  };

  allowApproveGuard?: {
    allowedSpender: Address;
    tokensToSetGuardTo: Address[];
  };
}

export type IProposeTxProperties = {
  protocolDaoAddress: Address;
  protocolTreasuryAddress: Address;
  proxyAdminAddress: Address;
};

export type IAddresses = IProposeTxProperties & IDeploymentsConfig;

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

export interface INotSureGuard extends RecordNumberString {
  name: string;
  destination: string;
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
  DhedgeStakingV2NFTJson?: Address;
  DhedgeStakingV2Proxy?: Address;
  DhedgeStakingV2?: Address;
  DynamicBondsProxy?: Address;
  DynamicBonds?: Address;
  ProxyAdmin?: Address;
  DhedgeNftTrackerStorageProxy: Address;
  DhedgeNftTrackerStorage: Address;
  RewardDistribution?: Address[];
  SlippageAccumulator?: Address;
  PoolTokenSwapperProxy?: Address;
  PoolTokenSwapper?: Address;

  // Contract Guards
  ClosedContractGuard?: Address;
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
  LyraOptionMarketContractGuard?: Address;
  ERC721ContractGuard?: Address;
  SynthetixFuturesMarketContractGuard?: Address;
  MaiVaultContractGuard?: Address;
  StargateRouterContractGuard?: Address;
  StargateLpStakingContractGuard?: Address;
  SynthetixPerpsV2MarketContractGuard?: Address;
  SynthRedeemerContractGuard?: Address;
  ZeroExContractGuard?: Address;
  VelodromeV2GaugeContractGuard?: Address;
  VelodromeV2RouterGuard?: Address;
  VelodromePairContractGuard?: Address;
  SynthetixV3ContractGuard?: Address;
  PoolTokenSwapperGuard?: Address;
  RamsesRouterContractGuard?: Address;
  RamsesGaugeContractGuard?: Address;
  RamsesXRamContractGuard?: Address;
  SynthetixV3SpotMarketContractGuard?: Address;
  SynthetixV3PerpsMarketContractGuard?: Address;
  SonneFinanceCTokenGuard?: Address;
  SonneFinanceComptrollerGuard?: Address;
  AaveMigrationHelperGuard?: Address;
  AaveDebtTokenContractGuard?: Address;
  FlatMoneyDelayedOrderContractGuard?: Address;
  OneInchV6Guard?: Address;
  VelodromeNonfungiblePositionGuard?: Address;
  VelodromeCLGaugeContractGuard?: Address;
  VelodromeNonfungiblePositionGuardOld?: Address;
  CompoundV3CometContractGuard?: Address;
  CompoundV3CometRewardsContractGuard?: Address;
  EasySwapperV2ContractGuard?: Address;
  RamsesNonfungiblePositionGuard?: Address;
  GmxExchangeRouterContractGuard?: Address;
  AngleDistributorContractGuard?: Address;
  PancakeNonfungiblePositionGuard?: Address;
  PancakeMasterChefV3Guard?: Address;
  AcrossContractGuard?: Address;
  SkyPSM3ContractGuard?: Address;
  FlatMoneyOptionsOrderAnnouncementGuard?: Address;
  FlatMoneyOptionsOrderExecutionGuard?: Address;
  FluidTokenContractGuard?: Address;
  OdosV2ContractGuard?: Address;
  FlatMoneyV2OrderAnnouncementGuard?: Address;
  FlatMoneyV2OrderExecutionGuard?: Address;
  PendleRouterV4ContractGuard?: Address;
  AllowApproveContractGuard?: Address;
  AaveLendingPoolGuardV3L2Pool?: Address;

  // Asset Guards
  OpenAssetGuard: Address;
  ERC20Guard?: Address;
  SushiLPAssetGuard?: Address;
  LendingEnabledAssetGuard?: Address;
  QuickLPAssetGuard?: Address;
  AaveLendingPoolAssetGuardV2?: Address;
  AaveLendingPoolAssetGuardV3?: Address;
  UniswapV3AssetGuard?: Address;
  ArrakisLiquidityGaugeV4AssetGuard?: Address;
  BalancerV2GaugeAssetGuard?: Address;
  VelodromeLPAssetGuard?: Address;
  LyraOptionMarketWrapperAssetGuard?: Address;
  SynthetixFuturesMarketAssetGuard?: Address;
  MaiVaultAssetGuard?: Address;
  StargateLPAssetGuard?: Address;
  SynthetixPerpsV2MarketAssetGuard?: Address;
  VelodromeV2LPAssetGuard?: Address;
  SynthetixV3AssetGuard?: Address;
  SynthetixV3PerpsAssetGuard?: Address;
  RamsesLPAssetGuard?: Address;
  FlatMoneyUNITAssetGuard?: Address;
  FlatMoneyCollateralAssetGuard?: Address;
  VelodromeCLAssetGuard?: Address;
  ByPassAssetGuard?: Address;
  FlatMoneyPerpMarketAssetGuard?: Address;
  RewardAssetGuard?: Address;
  CompoundV3CometAssetGuard?: Address;
  RamsesCLAssetGuard?: Address;
  EasySwapperV2UnrolledAssetsGuard: Address;
  GmxPerpMarketAssetGuard?: Address;
  PancakeCLAssetGuard?: Address;
  FlatMoneyOptionsMarketAssetGuard?: Address;
  FlatMoneyCollateralLendingEnabledGuard?: Address;
  FluidTokenAssetGuard?: Address;
  FlatMoneyV2PerpMarketAssetGuard?: Address;
  FlatMoneyV2UNITAssetGuard?: Address;
  PendlePTAssetGuard?: Address;

  // Libraries
  WeeklyWindowsHelper?: Address;
  GmxClaimableCollateralTrackerLib?: Address;
  GmxHelperLib?: Address;
  GmxAfterTxValidatorLib?: Address;
  GmxAfterExcutionLib?: Address;

  DhedgeEasySwapperProxy: Address;
  DhedgeEasySwapper: Address;
  DhedgeSuperSwapper: Address;
  DhedgeUniV3V2Router: Address;
  DhedgeVeloUniV2Router: Address;
  DhedgeVeloV2UniV2Router: Address;
  DhedgeRamsesUniV2Router: Address;

  Assets: TDeployedAsset[];
  RemovedAssets: TDeployedAsset[];

  EasySwapperV2: Address;
  EasySwapperV2Proxy: Address;
  WithdrawalVault: Address;
  WithdrawalVaultProxy: Address;
  PoolLimitOrderManager: Address;
  PoolLimitOrderManagerProxy: Address;
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
  | "MaticXPriceAggregator"
  | "ETHCrossAggregator"
  | "VelodromeV2TWAPAggregator"
  | "RamsesTWAPAggregator"
  | "RamsesVariableLPAggregator"
  | "SonneFinancePriceAggregator"
  | "FlatMoneyUNITPriceAggregator"
  | "ChainlinkPythPriceAggregator"
  | "CustomCrossAggregator"
  | "FluidTokenPriceAggregator"
  | "PythPriceAggregator"
  | "PendlePTPriceAggregator"
  | "ERC4626PriceAggregator";

export type ContractGuardType =
  | "BalancerV2GaugeContractGuard"
  | "VelodromeGaugeContractGuard"
  | "SynthetixFuturesMarketContractGuard"
  | "SynthetixPerpsV2MarketContractGuard"
  | "ArrakisLiquidityGaugeV4ContractGuard"
  | "MaiVaultContractGuard"
  | "VelodromeV2GaugeContractGuard"
  | "VelodromePairContractGuard"
  | "RamsesGaugeContractGuard"
  | "SonneFinanceCTokenGuard"
  | "CompoundV3CometContractGuard"
  | "FluidTokenContractGuard";

export type IVersion = {
  network: {
    chainId: number;
    name: string;
  };
  lastUpdated: string;
  contracts: IContracts;
  config: {
    easySwapperConfig?: IEasySwapperConfig;
    easySwapperV2?: IEasySwapperV2Config;
    poolLimitOrderManager: {
      authorizedKeeperAddresses: Address[];
    };
  };
};

export type IVersions = {
  [version: string]: IVersion;
};
