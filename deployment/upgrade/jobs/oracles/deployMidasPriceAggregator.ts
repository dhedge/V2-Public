import { HardhatRuntimeEnvironment } from "hardhat/types";

import { TAssetConfig, IMidasPriceAggregatorConfig } from "./oracleTypes";
import { tryVerify } from "../../../deploymentHelpers";
import { Address } from "../../../types";

const validateAssetConfig = (assetConfig: TAssetConfig): assetConfig is IMidasPriceAggregatorConfig => {
  const requiredFields = ["midasFeed", "heartbeat"];

  if (
    assetConfig.oracleType !== "MidasPriceAggregator" ||
    !requiredFields.every((field) => field in assetConfig.specificOracleConfig)
  ) {
    return false;
  }
  return true;
};

// A MidasPriceAggregator is a stateless immutable passthrough of (feed, heartbeat), so every asset
// sharing the same pair (e.g. the mToken at type 42 and its pending-redemption position at type 43,
// which price off the same NAV feed) can share a single instance. Deployed instances are cached for
// the lifetime of the deploy run and reused, so a run that adds both assets deploys the aggregator
// once instead of twice.
const deployedByFeedAndHeartbeat = new Map<string, Address>();

const deployMidasPriceAggregatorJob = async (
  hre: HardhatRuntimeEnvironment,
  assetConfig: IMidasPriceAggregatorConfig,
): Promise<Address> => {
  const config = assetConfig.specificOracleConfig;
  const cacheKey = `${config.midasFeed.toLowerCase()}:${config.heartbeat}`;

  const cached = deployedByFeedAndHeartbeat.get(cacheKey);
  if (cached) {
    console.log("Reusing MidasPriceAggregator already deployed this run for feed", config.midasFeed, "at", cached);
    return cached;
  }

  const MidasPriceAggregator = await hre.ethers.getContractFactory("MidasPriceAggregator");

  console.log("Deploying MidasPriceAggregator oracle...");

  const args: Parameters<typeof MidasPriceAggregator.deploy> = [config.midasFeed, config.heartbeat];

  const midasPriceAggregator = await MidasPriceAggregator.deploy(...args);
  await midasPriceAggregator.deployed();

  await tryVerify(
    hre,
    midasPriceAggregator.address,
    "contracts/priceAggregators/MidasPriceAggregator.sol:MidasPriceAggregator",
    args,
  );

  deployedByFeedAndHeartbeat.set(cacheKey, midasPriceAggregator.address);

  return midasPriceAggregator.address;
};

export const deployMidasPriceAggregator = async (
  hre: HardhatRuntimeEnvironment,
  assetConfig: TAssetConfig,
): Promise<Address> => {
  if (!validateAssetConfig(assetConfig)) {
    throw new Error(`${assetConfig.assetName} has not a valid config`);
  }

  const address = await deployMidasPriceAggregatorJob(hre, assetConfig);
  return address;
};
