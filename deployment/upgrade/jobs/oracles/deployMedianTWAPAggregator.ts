import { HardhatRuntimeEnvironment } from "hardhat/types";
import { tryVerify } from "../../../deploymentHelpers";
import { Address } from "../../../types";
import { TAssetConfig, IMedianTWAPAggregatorSpecificConfig, TOracleDeployer, IAssetConfig } from "./oracleTypes";

/**
 * Uniswap v2 pool TWAP oracle deployer
 * @param hre Hardhat Runtime Environment
 * @param oracleConfig Oracle configuration parameters
 * @returns Address of the deployed oracle
 */
export const deployMedianTWAPAggregator: TOracleDeployer = async (
  hre: HardhatRuntimeEnvironment,
  oracleConfig: TAssetConfig,
): Promise<Address> => {
  const ethers = hre.ethers;

  const twapConfig: IMedianTWAPAggregatorSpecificConfig = validateConfig(oracleConfig);

  const MedianTWAPAggregator = await ethers.getContractFactory("MedianTWAPAggregator");
  const medianTwapAggregator = await MedianTWAPAggregator.deploy(
    twapConfig.poolAddress,
    oracleConfig.assetAddress,
    twapConfig.pairTokenOracle,
    twapConfig.updateInterval,
    twapConfig.volatilityTripLimit,
  );
  await medianTwapAggregator.deployed();

  // wait 5 confirmations before verifying
  const tx = medianTwapAggregator.deployTransaction;
  await tx.wait(5);
  await tryVerify(
    hre,
    medianTwapAggregator.address,
    "contracts/priceAggregators/MedianTWAPAggregator.sol:MedianTWAPAggregator",
    [
      twapConfig.poolAddress,
      oracleConfig.assetAddress,
      twapConfig.pairTokenOracle,
      twapConfig.updateInterval,
      twapConfig.volatilityTripLimit,
    ],
  );

  await medianTwapAggregator.transferOwnership(twapConfig.owner);

  return medianTwapAggregator.address;
};

const isMedianTWAPAggregator = (
  oracleConfig: TAssetConfig,
): oracleConfig is IAssetConfig<"MedianTWAPAggregator", IMedianTWAPAggregatorSpecificConfig> => {
  const requiredFields = ["poolAddress", "pairTokenOracle", "updateInterval", "volatilityTripLimit", "owner"];
  const { specificOracleConfig } = oracleConfig;
  if (
    oracleConfig.oracleType != "MedianTWAPAggregator" ||
    !specificOracleConfig ||
    requiredFields.some((field) => !(field in oracleConfig.specificOracleConfig))
  ) {
    return false;
  }
  return true;
};

const validateConfig = (oracleConfig: TAssetConfig): IMedianTWAPAggregatorSpecificConfig => {
  const specificOracleConfig = oracleConfig.specificOracleConfig;
  if (!isMedianTWAPAggregator(oracleConfig)) {
    throw new Error("MedianTWAPAggregator config incorrect: " + oracleConfig.assetAddress);
  }

  return specificOracleConfig as IMedianTWAPAggregatorSpecificConfig;
};
