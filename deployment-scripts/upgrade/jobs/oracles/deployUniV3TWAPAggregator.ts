import { HardhatRuntimeEnvironment } from "hardhat/types";
import { tryVerify } from "../../../Helpers";
import { Address } from "../../../types";
import { TAssetConfig, IUniV3TWAPAggregatorSpecificConfig, TOracleDeployer, IAssetConfig } from "./oracleTypes";

export const deployUniV3TWAPAggregator: TOracleDeployer = async (
  hre: HardhatRuntimeEnvironment,
  oracleConfig: TAssetConfig,
): Promise<Address> => {
  const ethers = hre.ethers;

  const specificConfig: IUniV3TWAPAggregatorSpecificConfig = validateConfig(oracleConfig);

  const UniV3TWAPAggregator = await ethers.getContractFactory("UniV3TWAPAggregator");
  console.log("Deploying Median TWAP oracle..");
  const uniV3TWAPAggregator = await UniV3TWAPAggregator.deploy(
    specificConfig.pool,
    specificConfig.mainToken,
    specificConfig.pairTokenUsdAggregator,
    specificConfig.priceLowerLimit,
    specificConfig.priceUpperLimit,
    specificConfig.updateInterval,
  );
  await uniV3TWAPAggregator.deployed();

  // wait 5 confirmations before verifying
  const tx = uniV3TWAPAggregator.deployTransaction;
  await tx.wait(5);
  await tryVerify(
    hre,
    uniV3TWAPAggregator.address,
    "contracts/priceAggregators/UniV3TWAPAggregator.sol:UniV3TWAPAggregator",
    [
      specificConfig.pool,
      specificConfig.mainToken,
      specificConfig.pairTokenUsdAggregator,
      specificConfig.priceLowerLimit,
      specificConfig.priceUpperLimit,
      specificConfig.updateInterval,
    ],
  );
  return uniV3TWAPAggregator.address;
};

const isUniV3TWAPAggregator = (
  oracleConfig: TAssetConfig,
): oracleConfig is IAssetConfig<"UniV3TWAPAggregator", IUniV3TWAPAggregatorSpecificConfig> => {
  const requiredFields = [
    "pool",
    "mainToken",
    "pairTokenUsdAggregator",
    "priceLowerLimit",
    "priceUpperLimit",
    "updateInterval",
  ];
  const { specificOracleConfig } = oracleConfig;
  if (
    oracleConfig.oracleType != "UniV3TWAPAggregator" ||
    !specificOracleConfig ||
    requiredFields.some((field) => !(field in oracleConfig.specificOracleConfig))
  ) {
    return false;
  }
  return true;
};

const validateConfig = (oracleConfig: TAssetConfig): IUniV3TWAPAggregatorSpecificConfig => {
  const specificOracleConfig = oracleConfig.specificOracleConfig;
  if (!isUniV3TWAPAggregator(oracleConfig)) {
    throw new Error("UniV3TWAPAggregator config incorrect: " + oracleConfig.assetAddress);
  }

  return specificOracleConfig as IUniV3TWAPAggregatorSpecificConfig;
};
