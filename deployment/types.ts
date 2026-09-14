import { HardhatRuntimeEnvironment } from "hardhat/types";
import { BigNumber, BigNumberish } from "ethers";
import { RewardAssetSettingStruct } from "../types/RewardAssetGuard";
import { PoolSettingStruct, VirtualTokenOracleSettingStruct } from "../types/GmxExchangeRouterContractGuard";
import { RewardTokenConfigStruct } from "../types/AngleDistributorContractGuard";
import { RouteHintStruct } from "../types/DhedgeSuperSwapper";
import type { IContracts } from "./versionsContracts";

export type Address = string;

export interface IUpgradeConfigProposeTx {
  execute: boolean;
  restartnonce: boolean;
  useNonce: number;
  chainId: number;
}

/**
 * oldTag and newTag are always the same value: the single current key in
 * versions.json. Releases stopped being tagged after v2.12.0, so there is no
 * longer a previous/next version to distinguish - jobs read and write the same
 * entry. Both fields are retained only because ~500 job call sites reference
 * them; treat either as "the version entry being updated".
 */
export type IUpgradeConfig = IUpgradeConfigProposeTx & {
  oldTag: string;
  newTag: string;
};

export type IJob<T> = (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => Promise<T>;

// File Names
export interface IFileNames {
  versionsFileName: string;
  assetsFileName: string;
  contractGuardsFileName: string;
  assetGuardsFileName: string;
  // This file is an entry point for guards deprecation and is picked by a script. Copy here guards for deprecation.
  deprecatedContractGuardsFileName?: string;
  approvedPerpsFileName?: string;
}

interface IEasySwapperV2Config {
  customCooldownDepositsWhitelist: Address[];
}

interface IDeploymentsConfig {
  // Protocol settings
  assets?: {
    nativeAssetWrapper: Address;
    usdc?: Address;
    dht?: Address;
  };

  slippageAccumulator: {
    decayTime: number;
    maxCumulativeSlippage: number;
  };

  superSwapper?: {
    routeHints: RouteHintStruct[];
  };

  v2RouterAddresses?: Address[];

  rewardAssetSetting?: RewardAssetSettingStruct[];

  rewardDistribution?: {
    token: Address;
    amountPerSecond: BigNumberish;
    whitelistedPools: string[];
  }[];

  stakingV2?: {
    dhtCap: BigNumber;
    emissionsRate: number;
    whitelistedPools: { pool: Address; cap: BigNumber }[];
  };

  // Periphery
  easySwapperV2?: IEasySwapperV2Config;

  poolLimitOrderManager?: {
    defaultSlippageTolerance: number;
    settlementToken: Address;
    authorizedKeeperAddresses: Address[];
  };

  easyLimitBuyManager?: {
    permit2: Address;
    authorizedKeeperAddresses: Address[];
  };

  typedStructuredDataValidator?: {
    cowSwapOrder?: {
      gpv2Settlement: Address;
      maxUnfavorableDeviationBps: number;
    };
  };

  // Swap venues
  oneInchV6RouterAddress?: Address;

  kyberSwap?: {
    routerV2: Address;
  };

  uniV2?: {
    factory: Address;
  };

  uniV3?: {
    uniswapV3RouterAddress: Address;
    uniswapV3FactoryAddress: Address;
    uniSwapV3NonfungiblePositionManagerAddress?: Address;
  };

  quickswap?: {
    uniV2Factory: Address;
  };

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
    enabledGauges: Address[];
    voter: Address;
  };

  ramses?: {
    router: Address;
  };

  pancakeswap?: {
    nonfungiblePositionManager: Address;
    masterChefV3: Address;
  };

  // Lending and yield
  aaveV3?: {
    aaveLendingPoolAddress: Address;
    aaveIncentivesControllerAddress?: Address;
  };

  aaveMigrationHelper?: {
    migrationHelperAddress: Address;
    aaveV3DebtTokensWhitelist: Address[];
  };

  compoundV3?: {
    rewards: Address;
  };

  fluid?: {
    merkleDistributor?: Address;
  };

  pendle?: {
    pendleRouterV4: Address;
    knownMarkets: Address[];
    yieldContractFactory?: Address;
    staticRouter?: Address;
  };

  angleProtocol?: {
    distributor: Address;
    rewardTokenSupported: RewardTokenConfigStruct[];
  };

  // Flat Money
  flatMoney?: {
    delayedOrder?: Address;
    perpMarketWhitelistedVaults?: {
      poolLogic: Address;
      withdrawalAsset: Address;
    }[];
    swapper: Address;
  };

  flatMoneyV2?: {
    orderAnnouncementModule: Address;
    orderExecutionModule: Address;
    whitelistedVaults: {
      poolLogic: Address;
      withdrawalAsset: Address;
    }[];
  };

  flatMoneyOptions?: {
    orderAnnouncementModule: Address;
    orderExecutionModule: Address;
    flatcoinVault: Address;
    whitelistedVaultsForLP: PoolSettingStruct[];
    collateral: Address;
  };

  // Perps and RWA
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

  hyperliquid?: {
    admin: Address;
    maxSlippage: BigNumberish;
    apiWalletEnabledPools?: Address[]; // pools opted in to API wallet (agent) registration
  };

  dytm?: {
    dytmOffice: Address;
    dytmPeriphery: Address;
    accountSplitterAndMerger: Address;
    whitelistedPools: Address[];
    whitelistedMarkets: number[];
    maxDytmMarkets: number;
    mismatchDeltaNumerator: number;
  };

  ondo?: {
    gmTokenManager: Address;
    attestationOracle: {
      allowedUserId: string;
      maxProofAge: number;
      sanityDeviationBps: number;
      minQuoteValue: string;
      maxQuoteValue: string;
    };
    ondoGMSwapContractGuard?: {
      maxSlippagePerSwapBps: number;
    };
    ondoGMTokenAssetGuard?: {
      mismatchDeltaNumerator: number;
      minRedeemValue: string;
    };
    // Non-pool addresses authorised to call OndoGMSwap.swapExactInWithAttestation. Pools are
    // auto-authorised via poolFactory.isPool, so only contracts like DytmWithdrawProcessor go here.
    // Applied (diffed + setAuthorizedCaller) by ondoGMSwapConfigurationJob; tracked in versions.json.
    ondoGMSwap?: {
      authorizedCallers: Address[];
    };
  };

  midas?: {
    // Midas DepositVault (mToken minting entrypoint) — gets MidasDepositVaultContractGuard.
    depositVault: Address;
    // Midas RedemptionVault (mToken redemption entrypoint) — gets MidasRedemptionVaultContractGuard,
    // which is the integration's single owned contract (async request tracking + the pool whitelist).
    redemptionVault: Address;
    // Pools allowed to use the integration; seeds the redemption vault contract guard's whitelist.
    whitelistedPools: Address[];
  };

  // Bridging
  across?: {
    spokePool: Address;
    // Approved bridge destinations live in deployment/acrossRoutes.ts, shared across chains.
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

export type IVersion = {
  network: {
    chainId: number;
    name: string;
  };
  lastUpdated: string;
  contracts: IContracts;
  config: {
    easySwapperV2?: IEasySwapperV2Config;
    poolLimitOrderManager?: {
      authorizedKeeperAddresses: Address[];
    };
    easyLimitBuyManager?: {
      authorizedKeeperAddresses: Address[];
    };
    ondoGMSwap?: {
      authorizedCallers: Address[];
    };
    hyperliquidCoreWriterGuard?: {
      approvedPerps: { perpName: string; assetId: number; approved: boolean }[];
    };
  };
};

export type IVersions = {
  [version: string]: IVersion;
};
