import { HardhatRuntimeEnvironment } from "hardhat/types";
import { OracleType, TDeployedAsset } from "./oracleTypes";
import { deployDhedgePoolAggregator } from "./deployDhedgePoolAggregator";
import { deployUniV3TWAPAggregator } from "./deployUniV3TWAPAggregator";
import { deployUSDPriceAggregator } from "./deployUSDPriceAggregator";
import { checkChainlinkConfig } from "./checkChainlinkConfig";
import { TAssetConfig, TOracleDeployer } from "./oracleTypes";
import { checkDeployedConfig } from "./checkDeployedConfig";
import { deployVelodromeTWAPAggregator } from "./deployVelodromeTWAPAggregator";
import { deployVelodromeStableLPAggregator } from "./deployVelodromeStableLPAggregator";
import { deployVelodromeVariableLPAggregator } from "./deployVelodromeVariableLPAggregator";
import { deployETHCrossAggregator } from "./deployETHCrossAggregator";
import { deployFlatMoneyUNITPriceAggregator } from "./deployFlatMoneyUNITPriceAggregator";
import { deployChainlinkPythPriceAggregator } from "./deployChainlinkPythPriceAggregator";
import { deployChainlinkAggregatorWrapper } from "./deployChainlinkAggregatorWrapper";
import { deployChainlinkTWAPAggregator } from "./deployChainlinkTWAPAggregator";
import { deployCustomCrossAggregator } from "./deployCustomCrossAggregator";
import { deployFluidTokenPriceAggregator } from "./deployFluidTokenPriceAggregator";
import { deployPendlePTPriceAggregator } from "./deployPendlePTPriceAggregator";
import { deployERC4626PriceAggregator } from "./deployERC4626PriceAggregator";
import { deployHyperliquidSpotPriceAggregator } from "./deployHyperliquidSpotPriceAggregator";
import { deployOndoAttestationAggregator } from "./deployOndoAttestationAggregator";
import { deployMidasPriceAggregator } from "./deployMidasPriceAggregator";

export const getOracle = async (hre: HardhatRuntimeEnvironment, assetConfig: TAssetConfig): Promise<TDeployedAsset> => {
  const oracleAddress = await typeToDeployer[assetConfig.oracleType](hre, assetConfig);
  return {
    ...assetConfig,
    oracleAddress,
  };
};

type TOracleTypeToDeployer = {
  [K in OracleType]: TOracleDeployer;
};

const typeToDeployer: TOracleTypeToDeployer = {
  DHedgePoolAggregator: deployDhedgePoolAggregator,
  USDPriceAggregator: deployUSDPriceAggregator,
  UniV3TWAPAggregator: deployUniV3TWAPAggregator,
  ChainlinkAggregator: checkChainlinkConfig,
  DhedgeDeployedAggregator: checkDeployedConfig,
  VelodromeTWAPAggregator: (hre: HardhatRuntimeEnvironment, assetConfig: TAssetConfig) =>
    deployVelodromeTWAPAggregator(hre, assetConfig, "VelodromeTWAPAggregator"),
  VelodromeStableLPAggregator: deployVelodromeStableLPAggregator,
  VelodromeVariableLPAggregator: deployVelodromeVariableLPAggregator,
  ETHCrossAggregator: deployETHCrossAggregator,
  VelodromeV2TWAPAggregator: (hre: HardhatRuntimeEnvironment, assetConfig: TAssetConfig) =>
    deployVelodromeTWAPAggregator(hre, assetConfig, "VelodromeV2TWAPAggregator"),
  FlatMoneyUNITPriceAggregator: deployFlatMoneyUNITPriceAggregator,
  ChainlinkPythPriceAggregator: deployChainlinkPythPriceAggregator,
  ChainlinkAggregatorWrapper: deployChainlinkAggregatorWrapper,
  ChainlinkTWAPAggregator: deployChainlinkTWAPAggregator,
  CustomCrossAggregator: deployCustomCrossAggregator,
  FluidTokenPriceAggregator: deployFluidTokenPriceAggregator,
  PendlePTPriceAggregator: deployPendlePTPriceAggregator,
  ERC4626PriceAggregator: deployERC4626PriceAggregator,
  HyperliquidSpotPriceAggregator: deployHyperliquidSpotPriceAggregator,
  OndoAttestationAggregator: deployOndoAttestationAggregator,
  MidasPriceAggregator: deployMidasPriceAggregator,
};
