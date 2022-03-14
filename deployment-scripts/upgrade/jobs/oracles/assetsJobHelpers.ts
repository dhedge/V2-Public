import { HardhatRuntimeEnvironment } from "hardhat/types";
import { OracleType, TDeployedAsset } from "../../../types";
import { deployBalancerStablePoolAggregator } from "./deployBalancerStablePoolAggregator";
import { deployBalancerV2LPAggregator } from "./deployBalancerV2LPAggregator";
import { deployDhedgePoolAggregator } from "./deployDhedgePoolAggregator";
import { deployMedianTWAPAggregator } from "./deployMedianTWAPAggregator";
import { deploySynthPriceAggregator } from "./deploySynthPriceAggregator";
import { deployUniV2LPAggregator } from "./deployUniV2LPAggregator";
import { deployUniV3TWAPAggregator } from "./deployUniV3TWAPAggregator";
import { deployUSDPriceAggregator } from "./deployUSDPriceAggregator";
import { IAssetConfig, IChainlinkAggregatorSpecificConfig, TAssetConfig, TOracleDeployer } from "./oracleTypes";

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
  DHedgePoolAggregator: deployDhedgePoolAggregator,
  MedianTWAPAggregator: deployMedianTWAPAggregator,
  UniV2LPAggregator: deployUniV2LPAggregator,
  USDPriceAggregator: deployUSDPriceAggregator,
  SynthPriceAggregator: deploySynthPriceAggregator,
  UniV3TWAPAggregator: deployUniV3TWAPAggregator,
  ChainlinkAggregator: (_, oracleConfig) => {
    const isChainlink = (
      oracleConfig: TAssetConfig,
    ): oracleConfig is IAssetConfig<"ChainlinkAggregator", IChainlinkAggregatorSpecificConfig> => {
      if (
        oracleConfig.oracleType != "ChainlinkAggregator" ||
        !oracleConfig.specificOracleConfig ||
        !("chainlinkOracleAddress" in oracleConfig.specificOracleConfig)
      ) {
        return false;
      }
      return true;
    };
    if (!isChainlink(oracleConfig)) {
      throw new Error("ChainlinkAggregator incorrect");
    }
    return Promise.resolve(oracleConfig.specificOracleConfig.chainlinkOracleAddress);
  },
};
