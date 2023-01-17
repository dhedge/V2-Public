import { HardhatRuntimeEnvironment } from "hardhat/types";
import { tryVerify } from "../../../Helpers";
import { Address } from "../../../types";
import { TAssetConfig, IVelodromeTWAPAggregatorSpecificConfig, TOracleDeployer, IAssetConfig } from "./oracleTypes";

export const deployVelodromeTWAPAggregator: TOracleDeployer = async (
  hre: HardhatRuntimeEnvironment,
  oracleConfig: TAssetConfig,
): Promise<Address> => {
  const ethers = hre.ethers;

  const specificConfig: IVelodromeTWAPAggregatorSpecificConfig = validateConfig(oracleConfig);

  const VelodromeTWAPAggregator = await ethers.getContractFactory("VelodromeTWAPAggregator");
  console.log("Deploying VelodromeTWAPAggregator oracle..");
  const args: [Address, Address, Address, Address] = [
    specificConfig.pair,
    specificConfig.mainToken,
    specificConfig.pairToken,
    specificConfig.pairTokenUsdAggregator,
  ];
  const velodromeTWAPAggregator = await VelodromeTWAPAggregator.deploy(...args);
  await velodromeTWAPAggregator.deployed();

  // wait 5 confirmations before verifying
  const tx = velodromeTWAPAggregator.deployTransaction;
  await tx.wait(5);
  await tryVerify(
    hre,
    velodromeTWAPAggregator.address,
    "contracts/priceAggregators/VelodromeTWAPAggregator.sol:VelodromeTWAPAggregator",
    args,
  );
  return velodromeTWAPAggregator.address;
};

const isVelodromeTWAPAggregator = (
  oracleConfig: TAssetConfig,
): oracleConfig is IAssetConfig<"VelodromeTWAPAggregator", IVelodromeTWAPAggregatorSpecificConfig> => {
  const requiredFields = ["pair", "mainToken", "pairToken", "pairTokenUsdAggregator"];
  const { specificOracleConfig } = oracleConfig;
  if (
    oracleConfig.oracleType != "VelodromeTWAPAggregator" ||
    !specificOracleConfig ||
    requiredFields.some((field) => !(field in oracleConfig.specificOracleConfig))
  ) {
    return false;
  }
  return true;
};

const validateConfig = (oracleConfig: TAssetConfig): IVelodromeTWAPAggregatorSpecificConfig => {
  const specificOracleConfig = oracleConfig.specificOracleConfig;
  if (!isVelodromeTWAPAggregator(oracleConfig)) {
    throw new Error("VelodromeTWAPAggregator config incorrect: " + oracleConfig.assetAddress);
  }

  return specificOracleConfig as IVelodromeTWAPAggregatorSpecificConfig;
};
