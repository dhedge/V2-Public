import type { Address } from "./types";
import type { TDeployedAsset } from "./upgrade/jobs/oracles/oracleTypes";

// Contract names a chain's versions.json may record. Only the core protocol
// contracts are guaranteed to exist on every chain.
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
  DhedgeNftTrackerStorageProxy?: Address;
  DhedgeNftTrackerStorage?: Address;
  RewardDistribution?: Address[];
  SlippageAccumulator?: Address;
  ValueManipulationCheck?: Address;
  SwapperProxy?: Address;
  Swapper?: Address;

  // Contract Guards
  ClosedContractGuard?: Address;
  USDPriceAggregator?: Address;
  OneInchV4Guard?: Address;
  BalancerV2Guard?: Address;
  AaveIncentivesControllerV3Guard?: Address;
  UniswapV3NonfungiblePositionGuard?: Address;
  VelodromeV2GaugeContractGuard?: Address;
  VelodromeV2RouterGuard?: Address;
  VelodromePairContractGuard?: Address;
  AaveDebtTokenContractGuard?: Address;
  FlatMoneyDelayedOrderContractGuard?: Address;
  OneInchV6Guard?: Address;
  VelodromeNonfungiblePositionGuard?: Address;
  VelodromeCLGaugeContractGuard?: Address;
  VelodromeNonfungiblePositionGuardOld?: Address;
  CompoundV3CometContractGuard?: Address;
  CompoundV3CometRewardsContractGuard?: Address;
  EasySwapperV2ContractGuard?: Address;
  GmxExchangeRouterContractGuard?: Address;
  AngleDistributorContractGuard?: Address;
  PancakeNonfungiblePositionGuard?: Address;
  PancakeMasterChefV3Guard?: Address;
  AcrossContractGuard?: Address;
  FlatMoneyOptionsOrderAnnouncementGuard?: Address;
  FlatMoneyOptionsOrderExecutionGuard?: Address;
  FluidTokenContractGuard?: Address;
  FlatMoneyV2OrderAnnouncementGuard?: Address;
  FlatMoneyV2OrderExecutionGuard?: Address;
  PendleRouterV4ContractGuard?: Address;
  FluidMerkleDistributorContractGuard?: Address;
  KyberSwapRouterV2ContractGuard?: Address;
  LiquifiRewardsContractGuard?: Address;
  PoolLimitOrderManagerGuard?: Address;
  GPv2SettlementContractGuard?: Address;
  DytmOfficeContractGuard?: Address;
  HyperliquidCoreWriterContractGuard?: Address;
  HyperliquidCoreWriterContractGuardProxy?: Address;
  HyperliquidCoreDepositWalletContractGuard?: Address;
  HyperliquidWithdrawalManager?: Address;
  HyperliquidWithdrawalManagerProxy?: Address;

  // Asset Guards
  OpenAssetGuard?: Address;
  ERC20Guard?: Address;
  SushiLPAssetGuard?: Address;
  QuickLPAssetGuard?: Address;
  AaveLendingPoolAssetGuardV3?: Address;
  UniswapV3AssetGuard?: Address;
  VelodromeV2LPAssetGuard?: Address;
  FlatMoneyUNITAssetGuard?: Address;
  FlatMoneyCollateralAssetGuard?: Address;
  VelodromeCLAssetGuard?: Address;
  ByPassAssetGuard?: Address;
  FlatMoneyPerpMarketAssetGuard?: Address;
  RewardAssetGuard?: Address;
  CompoundV3CometAssetGuard?: Address;
  EasySwapperV2UnrolledAssetsGuard?: Address;
  GmxPerpMarketAssetGuard?: Address;
  PancakeCLAssetGuard?: Address;
  FlatMoneyOptionsMarketAssetGuard?: Address;
  FluidTokenAssetGuard?: Address;
  FlatMoneyV2PerpMarketAssetGuard?: Address;
  FlatMoneyV2UNITAssetGuard?: Address;
  FlatMoneyV2UNITOutsideWithdrawalAssetGuard?: Address;
  PendlePTAssetGuard?: Address;
  VirtualTokenAssetGuard?: Address;
  DytmOfficeAssetGuard?: Address;
  HyperliquidPositionGuard?: Address;
  HyperliquidSpotGuard?: Address;
  HyperliquidERC20Guard?: Address;

  // Libraries
  GmxClaimableCollateralTrackerLib?: Address;
  GmxHelperLib?: Address;
  GmxPerpMarketAssetGuardLib?: Address;
  GmxAfterTxValidatorLib?: Address;
  GmxAfterExecutionLib?: Address;
  PoolLogicLib?: Address;
  GmxEventUtils?: Address;

  DhedgeSuperSwapper?: Address;
  DhedgeUniV3V2Router?: Address;
  DhedgeVeloUniV2Router?: Address;
  DhedgeVeloV2UniV2Router?: Address;
  DhedgeRamsesUniV2Router?: Address;

  Assets: TDeployedAsset[];
  RemovedAssets?: TDeployedAsset[];

  DytmWithdrawProcessor?: Address;
  EasySwapperV2?: Address;
  EasySwapperV2Proxy?: Address;
  WithdrawalVault?: Address;
  WithdrawalVaultProxy?: Address;
  DytmWithdrawLib?: Address;
  PoolLimitOrderManager?: Address;
  PoolLimitOrderManagerProxy?: Address;
  EasyLimitBuyManager?: Address;
  TypedStructuredDataValidator?: Address;
  TypedStructuredDataValidatorProxy?: Address;
  ReferralManager?: Address;
  ReferralManagerProxy?: Address;
  OndoGMSwap?: Address;
  OndoGMSwapProxy?: Address;
  OndoGMSwapContractGuard?: Address;
  OndoGMTokenAssetGuard?: Address;
  OndoAttestationOracle?: Address;
  MidasDepositVaultContractGuard?: Address;
  MidasRedemptionVaultContractGuard?: Address;
  MidasMTokenAssetGuard?: Address;
  MidasPendingRedemptionAssetGuard?: Address;
  OndoAttestationOracleProxy?: Address;
  WithdrawalGuardian?: Address;
  WithdrawalGuardianProxy?: Address;
}
