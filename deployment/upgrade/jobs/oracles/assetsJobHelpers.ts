import { HardhatRuntimeEnvironment } from "hardhat/types";
import { OracleType, TDeployedAsset } from "../../../types";
import { deployBalancerStablePoolAggregator } from "./deployBalancerStablePoolAggregator";
import { deployBalancerComposableStablePoolAggregator } from "./deployBalancerComposableStablePoolAggregator";
import { deployBalancerV2LPAggregator } from "./deployBalancerV2LPAggregator";
import { deployDhedgePoolAggregator } from "./deployDhedgePoolAggregator";
import { deployMedianTWAPAggregator } from "./deployMedianTWAPAggregator";
import { deploySynthPriceAggregator } from "./deploySynthPriceAggregator";
import { deployUniV2LPAggregator } from "./deployUniV2LPAggregator";
import { deployUniV3TWAPAggregator } from "./deployUniV3TWAPAggregator";
import { deployUSDPriceAggregator } from "./deployUSDPriceAggregator";
import { deployMaticXPriceAggregator } from "./deployMaticXPriceAggregator";
import { checkChainlinkConfig } from "./checkChainlinkConfig";
import { TAssetConfig, TOracleDeployer } from "./oracleTypes";
import { checkDeployedConfig } from "./checkDeployedConfig";
import { deployDQUICKPriceAggregator } from "./deployDQUICKPriceAggregator";
import { deployVelodromeTWAPAggregator } from "./deployVelodromeTWAPAggregator";
import { deployVelodromeStableLPAggregator } from "./deployVelodromeStableLPAggregator";
import { deployVelodromeVariableLPAggregator } from "./deployVelodromeVariableLPAggregator";
import { deployETHCrossAggregator } from "./deployETHCrossAggregator";
import { deployRamsesTWAPAggregator } from "./deployRamsesTWAPAggregator";
import { deployRamsesVariableLPAggregator } from "./deployRamsesVariableLPAggregator";
import { deploySonneFinancePriceAggregator } from "./deploySonneFinancePriceAggregator";

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
  BalancerV2LPAggregator: deployBalancerV2LPAggregator,
  BalancerStablePoolAggregator: deployBalancerStablePoolAggregator,
  BalancerComposableStablePoolAggregator: deployBalancerComposableStablePoolAggregator,
  DHedgePoolAggregator: deployDhedgePoolAggregator,
  MedianTWAPAggregator: deployMedianTWAPAggregator,
  UniV2LPAggregator: deployUniV2LPAggregator,
  USDPriceAggregator: deployUSDPriceAggregator,
  SynthPriceAggregator: deploySynthPriceAggregator,
  UniV3TWAPAggregator: deployUniV3TWAPAggregator,
  ChainlinkAggregator: checkChainlinkConfig,
  DhedgeDeployedAggregator: checkDeployedConfig,
  DQUICKPriceAggregator: deployDQUICKPriceAggregator,
  MaticXPriceAggregator: deployMaticXPriceAggregator,
  VelodromeTWAPAggregator: (hre: HardhatRuntimeEnvironment, assetConfig: TAssetConfig) =>
    deployVelodromeTWAPAggregator(hre, assetConfig, "VelodromeTWAPAggregator"),
  VelodromeStableLPAggregator: deployVelodromeStableLPAggregator,
  VelodromeVariableLPAggregator: deployVelodromeVariableLPAggregator,
  ETHCrossAggregator: deployETHCrossAggregator,
  VelodromeV2TWAPAggregator: (hre: HardhatRuntimeEnvironment, assetConfig: TAssetConfig) =>
    deployVelodromeTWAPAggregator(hre, assetConfig, "VelodromeV2TWAPAggregator"),
  RamsesTWAPAggregator: deployRamsesTWAPAggregator,
  RamsesVariableLPAggregator: deployRamsesVariableLPAggregator,
  SonneFinancePriceAggregator: deploySonneFinancePriceAggregator,
};
