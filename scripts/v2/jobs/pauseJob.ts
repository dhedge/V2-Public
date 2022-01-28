import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx } from "../../Helpers";
import { IJob, IUpgradeConfig } from "../types";

export const pauseJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This should be types and optimally should not be mutated
  versions: any,
  _: {},
  __: {},
) => {
  const ethers = hre.ethers;

  const poolFactoryProxy = versions[config.oldTag].contracts.PoolFactoryProxy;
  const PoolFactory = await hre.artifacts.readArtifact("PoolFactory");
  const PoolFactoryABI = new ethers.utils.Interface(PoolFactory.abi);

  console.log("Will pause");
  if (config.execute) {
    const pauseABI = PoolFactoryABI.encodeFunctionData("pause", []);
    await proposeTx(poolFactoryProxy, pauseABI, "Pause Pool Factory", config.execute, config.restartnonce);
  }
};
