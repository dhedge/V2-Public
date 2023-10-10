import { HardhatRuntimeEnvironment } from "hardhat/types";
import { tryVerify } from "../../../deploymentHelpers";
import { Address } from "../../../types";
import { TAssetConfig, TOracleDeployer } from "./oracleTypes";

export const deployDhedgePoolAggregator: TOracleDeployer = async (
  hre: HardhatRuntimeEnvironment,
  oracleConfig: TAssetConfig,
): Promise<Address> => {
  const { ethers } = hre;
  const DHedgePoolAggregator = await ethers.getContractFactory("DHedgePoolAggregator");
  const dHedgePoolAggregator = await DHedgePoolAggregator.deploy(oracleConfig.assetAddress);
  await dHedgePoolAggregator.deployed();
  await tryVerify(
    hre,
    dHedgePoolAggregator.address,
    "contracts/priceAggregators/DHedgePoolAggregator.sol:DHedgePoolAggregator",
    [oracleConfig.assetAddress],
  );
  return dHedgePoolAggregator.address;
};
