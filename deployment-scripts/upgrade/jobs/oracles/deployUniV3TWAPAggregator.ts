import { HardhatRuntimeEnvironment } from "hardhat/types";
import { tryVerify } from "../../../Helpers";
import { Address } from "../../../types";
import { TAssetConfig, IUniV3TWAPAggregatorSpecificConfig, TOracleDeployer } from "./oracleTypes";

export const deployUniV3TWAPAggregator: TOracleDeployer = async (
  hre: HardhatRuntimeEnvironment,
  oracleConfig: TAssetConfig,
): Promise<Address> => {
  const ethers = hre.ethers;

  const specificConfig = validateConfig(oracleConfig);

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

const validateConfig = (oracleConfig: TAssetConfig): IUniV3TWAPAggregatorSpecificConfig => {
  const specificOracleConfig = oracleConfig.specificOracleConfig;

  throw new Error("Needs to be implemented");

  return specificOracleConfig as IUniV3TWAPAggregatorSpecificConfig;
};
