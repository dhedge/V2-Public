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
  | IAssetConfig<"ChainlinkAggregator", IChainlinkAggregatorSpecificConfig>
  | IAssetConfig<"DHedgePoolAggregator", undefined>
  | IAssetConfig<"MedianTWAPAggregator", IMedianTWAPAggregatorSpecificConfig>
  | IAssetConfig<"UniV3TWAPAggregator", IUniV3TWAPAggregatorSpecificConfig>
  | IAssetConfig<"SynthPriceAggregator", ISynthPriceAggregatorSpecificConfig>
  | IAssetConfig<"UniV2LPAggregator", IUniV2LPAggregatorSpecificConfig>
  | IAssetConfig<"USDPriceAggregator", undefined>
  | IAssetConfig<"BalancerV2LPAggregator", IBalancerV2LPAggregatorSpecificConfig>
  | IAssetConfig<"BalancerStablePoolAggregator", IBalancerStablePoolAggregatorSpecificConfig>;

export interface IChainlinkAggregatorSpecificConfig {
  chainlinkOracleAddress: Address;
}

export interface ISynthPriceAggregatorSpecificConfig {
  susdPriceAggregator: Address;
  tokenUSDPriceAggregator: Address;
}

export interface IUniV2LPAggregatorSpecificConfig {
  dhedgeFactoryProxy: Address;
}

export interface IBalancerV2LPAggregatorSpecificConfig {
  dhedgeFactoryProxy: Address;
}

export interface IBalancerStablePoolAggregatorSpecificConfig {
  dhedgeFactoryProxy: Address;
}

export interface IMedianTWAPAggregatorSpecificConfig {
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
