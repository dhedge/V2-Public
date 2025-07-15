import { HardhatRuntimeEnvironment } from "hardhat/types";

import { TAssetConfig, IChainlinkPythPriceAggregatorConfig } from "./oracleTypes";
import { tryVerify } from "../../../deploymentHelpers";
import { Address } from "../../../types";
import { arbitrumChainData } from "../../../../config/chainData/arbitrumData";

// check if the chainlink oracle set the asset config is compatible with GMX
// checking the chainlink oracle address and price feed multiplier in GMX data store
const validateChainlinkOracleForGmx = async (
  hre: HardhatRuntimeEnvironment,
  assetConfig: IChainlinkPythPriceAggregatorConfig,
) => {
  const ethers = hre.ethers;
  function hashData(dataTypes, dataValues) {
    const bytes = ethers.utils.defaultAbiCoder.encode(dataTypes, dataValues);
    const hash = ethers.utils.keccak256(ethers.utils.arrayify(bytes));

    return hash;
  }

  function hashString(string) {
    return hashData(["string"], [string]);
  }
  if (hre.network.name === "arbitrum") {
    const chainlinkOracleAddress = assetConfig.specificOracleConfig.chainlinkOracleAddress;
    const assetAddress = assetConfig.assetAddress;
    const gmxDataStore = await ethers.getContractAt("IGmxDataStore", arbitrumChainData.gmx.dataStore);
    const chainlinkOracleInGmx = await gmxDataStore.getAddress(
      hashData(["bytes32", "address"], [hashString("PRICE_FEED"), assetAddress]),
    );
    const priceFeeMultiplier = await gmxDataStore.getUint(
      hashData(["bytes32", "address"], [hashString("PRICE_FEED_MULTIPLIER"), assetAddress]),
    );
    console.log(`for ${assetConfig.assetName}:`);
    const oracleDecimals = await (
      await ethers.getContractAt("AggregatorV3Interface", chainlinkOracleAddress)
    ).decimals();
    const gmxOracleDecimals = await (
      await ethers.getContractAt("AggregatorV3Interface", chainlinkOracleInGmx)
    ).decimals();
    console.log(`Gmx chainlinkOracle: `, `${chainlinkOracleInGmx} (decimals: ${gmxOracleDecimals})`);
    console.log(`chainlinkOracleAddress: `, `${chainlinkOracleAddress} (decimals: ${oracleDecimals})`);
    console.log(`Gmx priceFeeMultiplier: `, priceFeeMultiplier.toString());

    const isSameOracleAddress = chainlinkOracleInGmx.toLowerCase() === chainlinkOracleAddress.toLowerCase();
    const isSameDecimals = oracleDecimals === gmxOracleDecimals;

    return (isSameOracleAddress || isSameDecimals) && priceFeeMultiplier.gt(0);
  }

  return true;
};

const validateAssetConfig = (assetConfig: TAssetConfig): assetConfig is IChainlinkPythPriceAggregatorConfig => {
  const requiredFields = ["chainlinkOracleMaxAge", "chainlinkOracleAddress", "pythOracleContract", "pythPriceId"];

  if (
    assetConfig.oracleType !== "ChainlinkPythPriceAggregator" ||
    !requiredFields.every((field) => field in assetConfig.specificOracleConfig)
  ) {
    return false;
  }
  return true;
};

const deployChainlinkPythPriceAggregatorJob = async (
  hre: HardhatRuntimeEnvironment,
  assetConfig: IChainlinkPythPriceAggregatorConfig,
) => {
  const ChainlinkPythPriceAggregator = await hre.ethers.getContractFactory("ChainlinkPythPriceAggregator");

  console.log("Deploying ChainlinkPythPriceAggregator oracle...");

  const args: Parameters<typeof ChainlinkPythPriceAggregator.deploy> = [
    assetConfig.assetAddress,
    assetConfig.specificOracleConfig.pythOracleContract,
    {
      onchainOracle: {
        maxAge: assetConfig.specificOracleConfig.chainlinkOracleMaxAge,
        oracleContract: assetConfig.specificOracleConfig.chainlinkOracleAddress,
      },
      offchainOracle: {
        maxAge: 86_400, // 86400 seconds => 24 hours,
        minConfidenceRatio: 50, // 100/50 => +-2% price deviation acceptable,
        priceId: assetConfig.specificOracleConfig.pythPriceId,
      },
    },
  ];
  const chainlinkPythPriceAggregator = await ChainlinkPythPriceAggregator.deploy(...args);
  await chainlinkPythPriceAggregator.deployed();

  await tryVerify(
    hre,
    chainlinkPythPriceAggregator.address,
    "contracts/priceAggregators/ChainlinkPythPriceAggregator.sol:ChainlinkPythPriceAggregator",
    args,
  );
  return chainlinkPythPriceAggregator.address;
};

export const deployChainlinkPythPriceAggregator = async (
  hre: HardhatRuntimeEnvironment,
  assetConfig: TAssetConfig,
): Promise<Address> => {
  if (!validateAssetConfig(assetConfig)) {
    throw new Error(`${assetConfig.assetName} has not a valid config`);
  }
  if (!(await validateChainlinkOracleForGmx(hre, assetConfig))) {
    throw new Error(`${assetConfig.assetName} chainlink oracle is not compatible with GMX`);
  } else {
    console.log(`${assetConfig.assetName} chainlink oracle is compatible with GMX`);
  }

  const address = await deployChainlinkPythPriceAggregatorJob(hre, assetConfig);
  return address;
};
