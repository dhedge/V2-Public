import { HardhatRuntimeEnvironment } from "hardhat/types";

import { TAssetConfig, IPendlePTPriceAggregatorConfig } from "./oracleTypes";
import { tryVerify } from "../../../deploymentHelpers";
import { Address } from "../../../types";

// PendleOracleType.PT_TO_SY — prices PT in terms of the SY token, which is a 1:1 wrap of the yield token
const PENDLE_ORACLE_PT_TO_SY = 0;
const PENDLE_ORACLE_TWAP_DURATION = 1800; // seconds

const PENDLE_CHAINLINK_ORACLE_FACTORY_ABI = [
  "function getOracle(address market, uint32 twapDuration, uint8 baseOracleType) view returns (address)",
  "function createOracle(address market, uint32 twapDuration, uint8 baseOracleType) returns (address)",
];

const validateAssetConfig = (assetConfig: TAssetConfig): assetConfig is IPendlePTPriceAggregatorConfig => {
  if (assetConfig.oracleType !== "PendlePTPriceAggregator") {
    return false;
  }
  const specificOracleConfig =
    assetConfig.specificOracleConfig as IPendlePTPriceAggregatorConfig["specificOracleConfig"];
  const requiredFields = ["syEquivalentYieldToken", "dhedgeFactoryProxy"];
  if (!requiredFields.every((field) => field in specificOracleConfig)) {
    return false;
  }
  // Oracle can be passed directly, or resolved via the factory + market pair
  return (
    !!specificOracleConfig.pendleChainlinkOracle ||
    (!!specificOracleConfig.pendleChainlinkOracleFactory && !!specificOracleConfig.pendleMarket)
  );
};

const resolvePendleChainlinkOracle = async (
  hre: HardhatRuntimeEnvironment,
  assetConfig: IPendlePTPriceAggregatorConfig,
): Promise<Address> => {
  const { pendleChainlinkOracle, pendleChainlinkOracleFactory, pendleMarket } = assetConfig.specificOracleConfig;

  if (pendleChainlinkOracle) return pendleChainlinkOracle;

  if (!pendleChainlinkOracleFactory || !pendleMarket) {
    throw new Error(`${assetConfig.assetName} is missing pendleChainlinkOracleFactory/pendleMarket config`);
  }

  const signer = (await hre.ethers.getSigners())[0];
  const factory = new hre.ethers.Contract(pendleChainlinkOracleFactory, PENDLE_CHAINLINK_ORACLE_FACTORY_ABI, signer);

  let oracle: Address = await factory.getOracle(pendleMarket, PENDLE_ORACLE_TWAP_DURATION, PENDLE_ORACLE_PT_TO_SY);
  if (oracle !== hre.ethers.constants.AddressZero) {
    console.log(`Found existing PendleChainlinkOracle for market ${pendleMarket} at ${oracle}`);
    return oracle;
  }

  // Permissionless creation; reverts inside Pendle's factory if the market's TWAP buffer is not ready
  console.log(`Creating PendleChainlinkOracle (PT_TO_SY, ${PENDLE_ORACLE_TWAP_DURATION}s) for market ${pendleMarket}`);
  const tx = await factory.createOracle(pendleMarket, PENDLE_ORACLE_TWAP_DURATION, PENDLE_ORACLE_PT_TO_SY);
  await tx.wait();

  oracle = await factory.getOracle(pendleMarket, PENDLE_ORACLE_TWAP_DURATION, PENDLE_ORACLE_PT_TO_SY);
  if (oracle === hre.ethers.constants.AddressZero) {
    throw new Error(`PendleChainlinkOracle creation failed for market ${pendleMarket}`);
  }
  console.log("PendleChainlinkOracle created at", oracle);
  return oracle;
};

const deployPendlePTPriceAggregatorJob = async (
  hre: HardhatRuntimeEnvironment,
  assetConfig: IPendlePTPriceAggregatorConfig,
) => {
  const factory = await hre.ethers.getContractAt("IPoolFactory", assetConfig.specificOracleConfig.dhedgeFactoryProxy);
  const assetHandler = await factory.getAssetHandler();

  const pendleChainlinkOracle = await resolvePendleChainlinkOracle(hre, assetConfig);

  const PendlePTPriceAggregator = await hre.ethers.getContractFactory("PendlePTPriceAggregator");

  console.log("Deploying PendlePTPriceAggregator oracle...");

  const args: [Address, Address, Address] = [
    assetConfig.specificOracleConfig.syEquivalentYieldToken,
    pendleChainlinkOracle,
    assetHandler,
  ];

  const pendlePTPriceAggregator = await PendlePTPriceAggregator.deploy(...args);
  await pendlePTPriceAggregator.deployed();

  await tryVerify(
    hre,
    pendlePTPriceAggregator.address,
    "contracts/priceAggregators/PendlePTPriceAggregator.sol:PendlePTPriceAggregator",
    args,
  );
  return pendlePTPriceAggregator.address;
};

export const deployPendlePTPriceAggregator = async (
  hre: HardhatRuntimeEnvironment,
  assetConfig: TAssetConfig,
): Promise<Address> => {
  if (!validateAssetConfig(assetConfig)) {
    throw new Error(`${assetConfig.assetName} has not a valid config`);
  }

  const address = await deployPendlePTPriceAggregatorJob(hre, assetConfig);
  return address;
};
