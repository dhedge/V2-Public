import { HardhatRuntimeEnvironment } from "hardhat/types";
import type { Address } from "../../../types";

export type OracleType =
  | "DhedgeDeployedAggregator"
  | "ChainlinkAggregator"
  | "DHedgePoolAggregator"
  | "USDPriceAggregator"
  | "UniV3TWAPAggregator"
  | "VelodromeTWAPAggregator"
  | "VelodromeStableLPAggregator"
  | "VelodromeVariableLPAggregator"
  | "ETHCrossAggregator"
  | "VelodromeV2TWAPAggregator"
  | "FlatMoneyUNITPriceAggregator"
  | "ChainlinkPythPriceAggregator"
  | "ChainlinkAggregatorWrapper"
  | "ChainlinkTWAPAggregator"
  | "CustomCrossAggregator"
  | "FluidTokenPriceAggregator"
  | "PendlePTPriceAggregator"
  | "ERC4626PriceAggregator"
  | "HyperliquidSpotPriceAggregator"
  | "OndoAttestationAggregator"
  | "MidasPriceAggregator";

export type ContractGuardType =
  | "VelodromeV2GaugeContractGuard"
  | "VelodromePairContractGuard"
  | "CompoundV3CometContractGuard"
  | "FluidTokenContractGuard";

export type TDeployedAsset = TAssetConfig & { oracleAddress: string };

export type TOracleDeployer = (hre: HardhatRuntimeEnvironment, oracleConfig: TAssetConfig) => Promise<Address>;

interface ITriggerChange {
  change?: string; // by modifying this it will trigger change detection can be date or reason
}

export interface IAssetConfig<TOracleType extends OracleType, TSpecificOracleConfig extends ITriggerChange> {
  oracleType: TOracleType;
  assetType: number;
  assetName: string;
  assetAddress: string;
  specificOracleConfig: TSpecificOracleConfig;
  assetMaxPriceAge?: number;
  specificContractGuardConfig?: {
    contractGuard: ContractGuardType;
    extraContractGuard?: ContractGuardType;
  } & ITriggerChange;
}

export type IETHCrossAggregatorConfig = IAssetConfig<"ETHCrossAggregator", IETHCrossAggregatorSpecificConfig>;
export type IVelodromeTWAPAggregatorConfig = IAssetConfig<
  "VelodromeTWAPAggregator",
  IVelodromeTWAPAggregatorSpecificConfig
>;
export type IVelodromeV2TWAPAggregatorConfig = IAssetConfig<
  "VelodromeV2TWAPAggregator",
  IVelodromeTWAPAggregatorSpecificConfig
>;
export type IFlatMoneyUNITPriceAggregatorConfig = IAssetConfig<
  "FlatMoneyUNITPriceAggregator",
  IFlatMoneyUNITPriceAggregatorConfigSpecificConfig
>;

export type IChainlinkPythPriceAggregatorConfig = IAssetConfig<
  "ChainlinkPythPriceAggregator",
  IChainlinkPythPriceAggregatorSpecificConfig
>;

export type IChainlinkAggregatorWrapperConfig = IAssetConfig<
  "ChainlinkAggregatorWrapper",
  IChainlinkAggregatorSpecificConfig
>;

export type ICustomCrossAggregatorConfig = IAssetConfig<"CustomCrossAggregator", ICustomCrossAggregatorSpecificConfig>;

export type IChainlinkTWAPAggregatorConfig = IAssetConfig<
  "ChainlinkTWAPAggregator",
  IChainlinkTWAPAggregatorSpecificConfig
>;

export type IFluidTokenPriceAggregatorConfig = IAssetConfig<
  "FluidTokenPriceAggregator",
  IFluidTokenPriceAggregatorSpecificConfig
>;

export type IUniV3TWAPAggregatorConfig = IAssetConfig<"UniV3TWAPAggregator", IUniV3TWAPAggregatorSpecificConfig>;

export type IPendlePTPriceAggregatorConfig = IAssetConfig<
  "PendlePTPriceAggregator",
  IPendlePTPriceAggregatorSpecificConfig
>;

export type IERC4626PriceAggregatorConfig = IAssetConfig<
  "ERC4626PriceAggregator",
  IERC4626PriceAggregatorSpecificConfig
>;

export type IHyperliquidSpotPriceAggregatorConfig = IAssetConfig<
  "HyperliquidSpotPriceAggregator",
  IHyperliquidSpotPriceAggregatorSpecificConfig
>;

export type IOndoAttestationAggregatorConfig = IAssetConfig<
  "OndoAttestationAggregator",
  IOndoAttestationAggregatorSpecificConfig
>;

export type IMidasPriceAggregatorConfig = IAssetConfig<"MidasPriceAggregator", IMidasPriceAggregatorSpecificConfig>;

export type TAssetConfig =
  | IAssetConfig<"DhedgeDeployedAggregator", IDhedgeDeployedAggregatorSpecificConfig>
  | IAssetConfig<"ChainlinkAggregator", IChainlinkAggregatorSpecificConfig>
  | IAssetConfig<"DHedgePoolAggregator", ITriggerChange>
  | IUniV3TWAPAggregatorConfig
  | IAssetConfig<"USDPriceAggregator", IUSDPriceAggregatorSpecificConfig>
  | IAssetConfig<"VelodromeStableLPAggregator", IVelodromeStableLPAggregatorSpecificConfig>
  | IAssetConfig<"VelodromeVariableLPAggregator", IVelodromeVariableLPAggregatorSpecificConfig>
  | IETHCrossAggregatorConfig
  | IVelodromeTWAPAggregatorConfig
  | IVelodromeV2TWAPAggregatorConfig
  | IFlatMoneyUNITPriceAggregatorConfig
  | IChainlinkPythPriceAggregatorConfig
  | IChainlinkAggregatorWrapperConfig
  | IChainlinkTWAPAggregatorConfig
  | ICustomCrossAggregatorConfig
  | IFluidTokenPriceAggregatorConfig
  | IPendlePTPriceAggregatorConfig
  | IERC4626PriceAggregatorConfig
  | IHyperliquidSpotPriceAggregatorConfig
  | IOndoAttestationAggregatorConfig
  | IMidasPriceAggregatorConfig;

export interface IChainlinkAggregatorSpecificConfig extends ITriggerChange {
  chainlinkOracleAddress: Address;
}
export interface IDhedgeDeployedAggregatorSpecificConfig extends ITriggerChange {
  alreadyDeployedOracleAddress: Address;
}

export interface IVelodromeStableLPAggregatorSpecificConfig extends ITriggerChange {
  dhedgeFactoryProxy: Address;
}
export interface IVelodromeVariableLPAggregatorSpecificConfig extends ITriggerChange {
  dhedgeFactoryProxy: Address;
}

export interface IUniV3TWAPAggregatorSpecificConfig extends ITriggerChange {
  pool: Address;
  mainToken: Address;
  pairTokenUsdAggregator: Address;
  updateInterval: number;
}

export interface IVelodromeTWAPAggregatorSpecificConfig extends ITriggerChange {
  pair: Address;
  mainToken: Address;
  pairToken: Address;
  pairTokenUsdAggregator: Address;
}

export interface IUSDPriceAggregatorSpecificConfig extends ITriggerChange {
  USDPriceOracleAddress: Address;
}

interface IETHCrossAggregatorSpecificConfig extends ITriggerChange {
  assetToEthChainlinkOracleAddress: Address;
  ethToUsdChainlinkOracleAddress: Address;
}

interface IFlatMoneyUNITPriceAggregatorConfigSpecificConfig extends ITriggerChange {
  flatMoneyViewerAddress: Address;
}

interface IChainlinkPythPriceAggregatorSpecificConfig extends ITriggerChange {
  chainlinkOracleMaxAge: number;
  chainlinkOracleAddress: Address;
  pythOracleContract: Address;
  pythPriceId: string;
}

interface ICustomCrossAggregatorSpecificConfig extends ITriggerChange {
  tokenToTokenAggregator: Address;
  tokenToUsdAggregator: Address;
}

interface IChainlinkTWAPAggregatorSpecificConfig extends ITriggerChange {
  maxPriceDifferencePercent: number;
  resultingPriceType: number;
  // Chainlink aggregator - either direct address or deploy a specific type
  chainlinkType?: "ERC4626PriceAggregator";
  chainlinkAggregatorAddress?: Address;
  erc4626Config?: IERC4626PriceAggregatorSpecificConfig;
  // TWAP aggregator - either direct address or deploy a specific type
  twapType: "UniV3TWAPAggregator" | "FluidDexObservationAggregator";
  twapAggregatorAddress?: Address;
  uniV3TWAPConfig?: IUniV3TWAPAggregatorSpecificConfig;
}

interface IFluidTokenPriceAggregatorSpecificConfig extends ITriggerChange {
  dhedgeFactoryProxy: Address;
}

interface IPendlePTPriceAggregatorSpecificConfig extends ITriggerChange {
  syEquivalentYieldToken: Address;
  dhedgeFactoryProxy: Address;
  // Either an already deployed PendleChainlinkOracle...
  pendleChainlinkOracle?: Address;
  // ...or the PendleChainlinkOracleFactory + market to get-or-create one (PT_TO_SY, 1800s TWAP).
  pendleChainlinkOracleFactory?: Address;
  pendleMarket?: Address;
}

export interface IERC4626PriceAggregatorSpecificConfig extends ITriggerChange {
  dhedgeFactoryProxy: Address;
}

export interface IHyperliquidSpotPriceAggregatorSpecificConfig extends ITriggerChange {
  spotIndex: number;
  usdcUsdFeed: Address;
}

interface IOndoAttestationAggregatorSpecificConfig extends ITriggerChange {
  ondoAttestationOracle: Address;
}

interface IMidasPriceAggregatorSpecificConfig extends ITriggerChange {
  // Midas CustomAggregatorV3CompatibleFeed (mToken/USD, 8 decimals) to wrap.
  midasFeed: Address;
  // Max acceptable staleness (seconds) of the feed's latest update; overrides the AssetHandler
  // default chainlink timeout (Midas pushes NAV ~daily with occasional multi-day gaps).
  heartbeat: number;
}
