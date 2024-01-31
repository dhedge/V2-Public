import { HardhatRuntimeEnvironment } from "hardhat/types";

import { TAssetConfig, IRamsesTWAPAggregatorConfig } from "./oracleTypes";
import { tryVerify } from "../../../deploymentHelpers";
import { Address } from "../../../types";

const validateAssetConfig = (oracleConfig: TAssetConfig): oracleConfig is IRamsesTWAPAggregatorConfig => {
  const requiredFields = ["pair", "mainToken", "pairToken", "pairTokenUsdAggregator"];
  if (
    oracleConfig.oracleType !== "RamsesTWAPAggregator" ||
    !requiredFields.every((field) => field in oracleConfig.specificOracleConfig)
  ) {
    return false;
  }
  return true;
};

const deployRamsesTWAPAggregatorJob = async (
  hre: HardhatRuntimeEnvironment,
  assetConfig: IRamsesTWAPAggregatorConfig,
) => {
  const RamsesTWAPAggregator = await hre.ethers.getContractFactory("RamsesTWAPAggregator");

  console.log("Deploying RamsesTWAPAggregator oracle...");

  const args: [Address, Address, Address, Address] = [
    assetConfig.specificOracleConfig.pair,
    assetConfig.specificOracleConfig.mainToken,
    assetConfig.specificOracleConfig.pairToken,
    assetConfig.specificOracleConfig.pairTokenUsdAggregator,
  ];
  const ramsesTWAPAggregator = await RamsesTWAPAggregator.deploy(...args);
  await ramsesTWAPAggregator.deployed();

  await tryVerify(
    hre,
    ramsesTWAPAggregator.address,
    "contracts/priceAggregators/RamsesTWAPAggregator.sol:RamsesTWAPAggregator",
    args,
  );
  return ramsesTWAPAggregator.address;
};

export const deployRamsesTWAPAggregator = async (
  hre: HardhatRuntimeEnvironment,
  assetConfig: TAssetConfig,
): Promise<Address> => {
  if (!validateAssetConfig(assetConfig)) {
    throw new Error(`${assetConfig.assetName} has not a valid config`);
  }

  const address = await deployRamsesTWAPAggregatorJob(hre, assetConfig);
  return address;
};
