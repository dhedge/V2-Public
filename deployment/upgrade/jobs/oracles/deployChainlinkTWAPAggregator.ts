import { HardhatRuntimeEnvironment } from "hardhat/types";

import { TAssetConfig, IChainlinkTWAPAggregatorConfig, IUniV3TWAPAggregatorSpecificConfig } from "./oracleTypes";
import { tryVerify } from "../../../deploymentHelpers";
import { Address } from "../../../types";
import { deployERC4626PriceAggregatorJob } from "./deployERC4626PriceAggregator";

const validateAssetConfig = (oracleConfig: TAssetConfig): oracleConfig is IChainlinkTWAPAggregatorConfig => {
  if (
    oracleConfig.oracleType !== "ChainlinkTWAPAggregator" ||
    !oracleConfig.specificOracleConfig.maxPriceDifferencePercent ||
    oracleConfig.specificOracleConfig.resultingPriceType === undefined ||
    !oracleConfig.specificOracleConfig.twapType
  ) {
    return false;
  }

  // Must have either chainlinkAggregatorAddress OR chainlinkType with config
  const hasChainlinkAddress = !!oracleConfig.specificOracleConfig.chainlinkAggregatorAddress;
  const hasChainlinkType = !!oracleConfig.specificOracleConfig.chainlinkType;
  if (!hasChainlinkAddress && !hasChainlinkType) {
    return false;
  }

  // Validate ERC4626 config if chainlinkType is ERC4626PriceAggregator
  if (oracleConfig.specificOracleConfig.chainlinkType === "ERC4626PriceAggregator") {
    const erc4626Config = oracleConfig.specificOracleConfig.erc4626Config;
    if (!erc4626Config || !erc4626Config.dhedgeFactoryProxy) {
      return false;
    }
  }

  // Must have either twapAggregatorAddress OR uniV3TWAPConfig
  const hasTwapAddress = !!oracleConfig.specificOracleConfig.twapAggregatorAddress;
  const hasUniV3Config = !!oracleConfig.specificOracleConfig.uniV3TWAPConfig;

  if (!hasTwapAddress && !hasUniV3Config) {
    return false;
  }

  // Validate UniV3-specific config if twapType is UniV3TWAPAggregator
  if (oracleConfig.specificOracleConfig.twapType === "UniV3TWAPAggregator" && hasUniV3Config) {
    const uniV3Config = oracleConfig.specificOracleConfig.uniV3TWAPConfig;
    if (
      !uniV3Config ||
      !uniV3Config.pool ||
      !uniV3Config.mainToken ||
      !uniV3Config.pairTokenUsdAggregator ||
      typeof uniV3Config.updateInterval !== "number"
    ) {
      return false;
    }
  }

  return true;
};

const deployUniV3TWAPAggregatorHelper = async (
  hre: HardhatRuntimeEnvironment,
  uniV3Config: IUniV3TWAPAggregatorSpecificConfig,
): Promise<Address> => {
  console.log("Deploying UniV3TWAPAggregator oracle for ChainlinkTWAPAggregator...");

  const UniV3TWAPAggregator = await hre.ethers.getContractFactory("UniV3TWAPAggregator");
  const uniV3TWAPAggregator = await UniV3TWAPAggregator.deploy(
    uniV3Config.pool,
    uniV3Config.mainToken,
    uniV3Config.pairTokenUsdAggregator,
    uniV3Config.updateInterval,
  );
  await uniV3TWAPAggregator.deployed();

  await tryVerify(
    hre,
    uniV3TWAPAggregator.address,
    "contracts/priceAggregators/UniV3TWAPAggregator.sol:UniV3TWAPAggregator",
    [uniV3Config.pool, uniV3Config.mainToken, uniV3Config.pairTokenUsdAggregator, uniV3Config.updateInterval],
  );

  return uniV3TWAPAggregator.address;
};

const deployChainlinkTWAPAggregatorJob = async (
  hre: HardhatRuntimeEnvironment,
  assetConfig: IChainlinkTWAPAggregatorConfig,
) => {
  let chainlinkAggregatorAddress: Address;

  // Determine Chainlink aggregator address - either use provided address or deploy based on chainlinkType
  if (assetConfig.specificOracleConfig.chainlinkAggregatorAddress) {
    chainlinkAggregatorAddress = assetConfig.specificOracleConfig.chainlinkAggregatorAddress;
    console.log(`Using existing Chainlink aggregator: ${chainlinkAggregatorAddress}`);
  } else if (
    assetConfig.specificOracleConfig.chainlinkType === "ERC4626PriceAggregator" &&
    assetConfig.specificOracleConfig.erc4626Config
  ) {
    chainlinkAggregatorAddress = await deployERC4626PriceAggregatorJob(
      hre,
      assetConfig.assetAddress,
      assetConfig.specificOracleConfig.erc4626Config.dhedgeFactoryProxy,
    );
    console.log(`Deployed new ERC4626PriceAggregator: ${chainlinkAggregatorAddress}`);
  } else {
    throw new Error(
      `Must provide either chainlinkAggregatorAddress or chainlinkType with config. Asset: ${assetConfig.assetName}`,
    );
  }

  let twapAggregatorAddress: Address;

  // Determine TWAP aggregator address - either use provided address or deploy based on twapType
  if (assetConfig.specificOracleConfig.twapAggregatorAddress) {
    twapAggregatorAddress = assetConfig.specificOracleConfig.twapAggregatorAddress;
    console.log(`Using existing TWAP aggregator: ${twapAggregatorAddress}`);
  } else if (
    assetConfig.specificOracleConfig.twapType === "UniV3TWAPAggregator" &&
    assetConfig.specificOracleConfig.uniV3TWAPConfig
  ) {
    twapAggregatorAddress = await deployUniV3TWAPAggregatorHelper(
      hre,
      assetConfig.specificOracleConfig.uniV3TWAPConfig,
    );
    console.log(`Deployed new UniV3TWAPAggregator: ${twapAggregatorAddress}`);
  } else if (assetConfig.specificOracleConfig.twapType === "FluidDexObservationAggregator") {
    throw new Error(
      `FluidDexObservationAggregator requires twapAggregatorAddress to be provided (already deployed). Asset: ${assetConfig.assetName}`,
    );
  } else {
    throw new Error(`Unsupported twapType "${assetConfig.specificOracleConfig.twapType}" or missing config`);
  }

  const ChainlinkTWAPAggregatorFactory = await hre.ethers.getContractFactory("ChainlinkTWAPAggregator");

  console.log("Deploying ChainlinkTWAPAggregator oracle...");

  const args: [Address, Address, number, number] = [
    chainlinkAggregatorAddress,
    twapAggregatorAddress,
    assetConfig.specificOracleConfig.maxPriceDifferencePercent,
    assetConfig.specificOracleConfig.resultingPriceType,
  ];

  const chainlinkTWAPAggregator = await ChainlinkTWAPAggregatorFactory.deploy(...args);
  await chainlinkTWAPAggregator.deployed();

  await tryVerify(
    hre,
    chainlinkTWAPAggregator.address,
    "contracts/priceAggregators/ChainlinkTWAPAggregator.sol:ChainlinkTWAPAggregator",
    args,
  );
  return chainlinkTWAPAggregator.address;
};

export const deployChainlinkTWAPAggregator = async (
  hre: HardhatRuntimeEnvironment,
  assetConfig: TAssetConfig,
): Promise<Address> => {
  if (!validateAssetConfig(assetConfig)) {
    throw new Error(`${assetConfig.assetName} has not a valid ChainlinkTWAPAggregator config`);
  }
  const address = await deployChainlinkTWAPAggregatorJob(hre, assetConfig);
  return address;
};
