import { HardhatRuntimeEnvironment } from "hardhat/types";

import { IAssetOracle } from "./deploy-asset-oracles";
import { tryVerify } from "../Helpers";

export const deployUniV2TwapOracle = async (hre: HardhatRuntimeEnvironment, twapOracle: IAssetOracle) => {
  const ethers = hre.ethers;

  await hre.run("compile:one", { contractName: "MedianTWAPAggregator" });

  checkTwapConfig(twapOracle);

  const MedianTWAPAggregator = await ethers.getContractFactory("MedianTWAPAggregator");
  console.log(`Deploying ${twapOracle.name}..`);
  const medianTwapAggregator = await MedianTWAPAggregator.deploy(
    twapOracle.poolAddress,
    twapOracle.assetAddress,
    twapOracle.pairTokenOracle,
    twapOracle.updateInterval!,
    twapOracle.volatilityTripLimit!,
  );
  await medianTwapAggregator.deployed();

  // wait 5 confirmations before verifying
  const tx = medianTwapAggregator.deployTransaction;
  await tx.wait(5);
  console.log(`Median TWAP oracle for ${twapOracle.name} deployed at ${medianTwapAggregator.address}`);
  await tryVerify(
    hre,
    medianTwapAggregator.address,
    "contracts/priceAggregators/MedianTWAPAggregator.sol:MedianTWAPAggregator",
    [
      twapOracle.poolAddress,
      twapOracle.assetAddress,
      twapOracle.pairTokenOracle,
      twapOracle.updateInterval,
      twapOracle.volatilityTripLimit,
    ],
  );

  return {
    name: twapOracle.name,
    oracleName: "MedianTWAPAggregator",
    assetAddress: twapOracle.assetAddress,
    oracleAddress: medianTwapAggregator.address,
  };
};

const checkTwapConfig = (twapOracle: IAssetOracle) => {
  if (!twapOracle.updateInterval) {
    throw new Error(`TWAP Oracle ${twapOracle.name} is missing updateInterval setting`);
  }
  if (!twapOracle.volatilityTripLimit) {
    throw new Error(`TWAP Oracle ${twapOracle.name} is missing volatilityTripLimit setting`);
  }
};
