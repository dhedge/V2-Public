import { HardhatRuntimeEnvironment } from "hardhat/types";
import { tryVerify } from "../../../Helpers";
import { Address } from "../../../types";
import { TAssetConfig, IMedianTWAPAggregatorConfig, TOracleDeployer } from "./oracleTypes";

export const deployMedianTWAPAggregator: TOracleDeployer = async (
  hre: HardhatRuntimeEnvironment,
  oracleConfig: TAssetConfig,
): Promise<Address> => {
  const ethers = hre.ethers;

  const twapConfig: IMedianTWAPAggregatorConfig = validateConfig(oracleConfig);

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

  return medianTwapAggregator.address;
};

const validateConfig = (oracleConfig: TAssetConfig): IMedianTWAPAggregatorConfig => {
  const specificOracleConfig = oracleConfig.specificOracleConfig;

  throw new Error("Needs to be implemented");

  return specificOracleConfig as IMedianTWAPAggregatorConfig;
};
