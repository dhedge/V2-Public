import { HardhatRuntimeEnvironment } from "hardhat/types";
import { Address, ContractGuardType, OracleType } from "../../../types";

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
export type ISonneFinancePriceAggregatorConfig = IAssetConfig<
  "SonneFinancePriceAggregator",
  ISonneFinancePriceAggregatorSpecificConfig
>;

export type IRamsesTWAPAggregatorConfig = IAssetConfig<"RamsesTWAPAggregator", IVelodromeTWAPAggregatorSpecificConfig>;
export type IRamsesLPVariableAggregatorConfig = IAssetConfig<
  "RamsesVariableLPAggregator",
  IVelodromeVariableLPAggregatorSpecificConfig
>;
export type IFlatMoneyUNITPriceAggregatorConfig = IAssetConfig<
  "FlatMoneyUNITPriceAggregator",
  IFlatMoneyUNITPriceAggregatorConfigSpecificConfig
>;

export type IChainlinkPythPriceAggregatorConfig = IAssetConfig<
  "ChainlinkPythPriceAggregator",
  IChainlinkPythPriceAggregatorSpecificConfig
>;

export type ICustomCrossAggregatorConfig = IAssetConfig<"CustomCrossAggregator", ICustomCrossAggregatorSpecificConfig>;

export type IFluidTokenPriceAggregatorConfig = IAssetConfig<
  "FluidTokenPriceAggregator",
  IFluidTokenPriceAggregatorSpecificConfig
>;

export type IPythPriceAggregatorConfig = IAssetConfig<"PythPriceAggregator", IPythPriceAggregatorSpecificConfig>;

export type IUniV3TWAPAggregatorConfig = IAssetConfig<"UniV3TWAPAggregator", IUniV3TWAPAggregatorSpecificConfig>;

export type IPendlePTPriceAggregatorConfig = IAssetConfig<
  "PendlePTPriceAggregator",
  IPendlePTPriceAggregatorSpecificConfig
>;

export type IERC4626PriceAggregatorConfig = IAssetConfig<
  "ERC4626PriceAggregator",
  IERC4626PriceAggregatorSpecificConfig
>;

export type TAssetConfig =
  | IAssetConfig<"DhedgeDeployedAggregator", IDhedgeDeployedAggregatorSpecificConfig>
  | IAssetConfig<"ChainlinkAggregator", IChainlinkAggregatorSpecificConfig>
  | IAssetConfig<"DHedgePoolAggregator", ITriggerChange>
  | IAssetConfig<"MedianTWAPAggregator", IMedianTWAPAggregatorSpecificConfig>
  | IUniV3TWAPAggregatorConfig
  | IAssetConfig<"SynthPriceAggregator", ISynthPriceAggregatorSpecificConfig>
  | IAssetConfig<"UniV2LPAggregator", IUniV2LPAggregatorSpecificConfig>
  | IAssetConfig<"USDPriceAggregator", IUSDPriceAggregatorSpecificConfig>
  | IAssetConfig<"BalancerV2LPAggregator", IBalancerV2LPAggregatorSpecificConfig>
  | IAssetConfig<"BalancerStablePoolAggregator", IBalancerStablePoolAggregatorSpecificConfig>
  | IAssetConfig<"BalancerComposableStablePoolAggregator", IBalancerStablePoolAggregatorSpecificConfig>
  | IAssetConfig<"DQUICKPriceAggregator", IDQUICKPriceAggregatorSpecificConfig>
  | IAssetConfig<"MaticXPriceAggregator", IMaticXPriceAggregatorSpecificConfig>
  | IAssetConfig<"VelodromeStableLPAggregator", IVelodromeStableLPAggregatorSpecificConfig>
  | IAssetConfig<"VelodromeVariableLPAggregator", IVelodromeVariableLPAggregatorSpecificConfig>
  | IETHCrossAggregatorConfig
  | IVelodromeTWAPAggregatorConfig
  | IVelodromeV2TWAPAggregatorConfig
  | IRamsesTWAPAggregatorConfig
  | IRamsesLPVariableAggregatorConfig
  | ISonneFinancePriceAggregatorConfig
  | IFlatMoneyUNITPriceAggregatorConfig
  | IChainlinkPythPriceAggregatorConfig
  | ICustomCrossAggregatorConfig
  | IFluidTokenPriceAggregatorConfig
  | IPythPriceAggregatorConfig
  | IPendlePTPriceAggregatorConfig
  | IERC4626PriceAggregatorConfig;

export interface IChainlinkAggregatorSpecificConfig extends ITriggerChange {
  chainlinkOracleAddress: Address;
}
export interface IDhedgeDeployedAggregatorSpecificConfig extends ITriggerChange {
  alreadyDeployedOracleAddress: Address;
}

export interface ISynthPriceAggregatorSpecificConfig extends ITriggerChange {
  susdPriceAggregator: Address;
  tokenUSDPriceAggregator: Address;
}

export interface IUniV2LPAggregatorSpecificConfig extends ITriggerChange {
  dhedgeFactoryProxy: Address;
}
export interface IVelodromeStableLPAggregatorSpecificConfig extends ITriggerChange {
  dhedgeFactoryProxy: Address;
}
export interface IVelodromeVariableLPAggregatorSpecificConfig extends ITriggerChange {
  dhedgeFactoryProxy: Address;
}

export interface IBalancerV2LPAggregatorSpecificConfig extends ITriggerChange {
  dhedgeFactoryProxy: Address;
}

export interface IMaticXPriceAggregatorSpecificConfig extends ITriggerChange {
  Matic: Address;
  MaticX: Address;
  MaticXPool: Address;
  dhedgeFactoryProxy: Address;
}

export interface IBalancerStablePoolAggregatorSpecificConfig extends ITriggerChange {
  dhedgeFactoryProxy: Address;
}

export interface IMedianTWAPAggregatorSpecificConfig extends ITriggerChange {
  poolAddress: string;
  pairTokenOracle: string;
  updateInterval: number;
  volatilityTripLimit: number;
  owner: string;
}

export interface IUniV3TWAPAggregatorSpecificConfig extends ITriggerChange {
  pool: Address;
  mainToken: Address;
  pairTokenUsdAggregator: Address;
  priceLowerLimit: number;
  priceUpperLimit: number;
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

export interface IDQUICKPriceAggregatorSpecificConfig extends ITriggerChange {
  QUICK: Address;
  dQUICK: Address;
  dhedgeFactoryProxy: Address;
}

export interface ISonneFinancePriceAggregatorSpecificConfig extends ITriggerChange {
  comptroller: Address;
  initialExchangeRateMantissa: number;
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

interface IFluidTokenPriceAggregatorSpecificConfig extends ITriggerChange {
  dhedgeFactoryProxy: Address;
}

interface IPythPriceAggregatorSpecificConfig extends ITriggerChange {
  maxAge: number;
  pythOracleContract: Address;
  priceId: string;
}

interface IPendlePTPriceAggregatorSpecificConfig extends ITriggerChange {
  syEquivalentYieldToken: Address;
  pendleChainlinkOracle: Address;
  dhedgeFactoryProxy: Address;
}

interface IERC4626PriceAggregatorSpecificConfig extends ITriggerChange {
  dhedgeFactoryProxy: Address;
}
