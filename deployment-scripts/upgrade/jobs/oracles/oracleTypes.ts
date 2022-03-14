import { HardhatRuntimeEnvironment } from "hardhat/types";
import { Address, OracleType } from "../../../types";

export type TOracleDeployer = (hre: HardhatRuntimeEnvironment, oracleConfig: TAssetConfig) => Promise<Address>;

export interface IAssetConfig<TOracleType extends OracleType, TSpecificOracleConfig> {
  oracleType: TOracleType;
  assetType: number;
  assetName: string;
  assetAddress: string;
  specificOracleConfig: TSpecificOracleConfig;
}

export type TAssetConfig =
  | IAssetConfig<"ChainlinkAggregator", IChainlinkAggregatorConfig>
  | IAssetConfig<"DHedgePoolAggregator", undefined>
  | IAssetConfig<"MedianTWAPAggregator", IMedianTWAPAggregatorConfig>
  | IAssetConfig<"UniV3TWAPAggregator", IUniV3TWAPAggregatorSpecificConfig>
  | IAssetConfig<"SynthPriceAggregator", ISynthPriceAggregatorConfig>
  | IAssetConfig<"UniV2LPAggregator", IUniV2LPAggregatorConfig>
  | IAssetConfig<"USDPriceAggregator", undefined>
  | IAssetConfig<"BalancerV2LPAggregator", IBalancerV2LPAggregatorConfig>
  | IAssetConfig<"BalancerStablePoolAggregator", undefined>;

export interface IChainlinkAggregatorConfig {
  chainlinkOracleAddress: Address;
}

export interface ISynthPriceAggregatorConfig {
  susdPriceAggregator: Address;
  tokenUSDPriceAggregator: Address;
}

export interface IUniV2LPAggregatorConfig {
  dhedgeFactoryProxy: Address;
}

export interface IBalancerV2LPAggregatorConfig {
  dhedgeFactoryProxy: Address;
  balancerV2VaultAddress: Address;
}

export interface IBalancerStablePoolAggregatorConfig {
  dhedgeFactoryProxy: Address;
}

export interface IMedianTWAPAggregatorConfig {
  poolAddress: string;
  pairTokenOracle: string;
  updateInterval: number;
  volatilityTripLimit: number;
}

export interface IUniV3TWAPAggregatorSpecificConfig {
  pool: Address;
  mainToken: Address;
  pairTokenUsdAggregator: Address;
  priceLowerLimit: number;
  priceUpperLimit: number;
  updateInterval: number;
}
