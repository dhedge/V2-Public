import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx } from "../../deploymentHelpers";
import { IJob, IProposeTxProperties, IUpgradeConfig, IVersions, IFileNames } from "../../types";

export const pauseJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  _filenames: IFileNames,
  addresses: IProposeTxProperties,
) => {
  const ethers = hre.ethers;

  const poolFactoryProxy = versions[config.oldTag].contracts.PoolFactoryProxy;
  const PoolFactory = await hre.artifacts.readArtifact("PoolFactory");
  const PoolFactoryABI = new ethers.utils.Interface(PoolFactory.abi);

  console.log("Will pause");
  if (config.execute) {
    const pauseABI = PoolFactoryABI.encodeFunctionData("pause", []);
    await proposeTx(poolFactoryProxy, pauseABI, "Pause Pool Factory", config, addresses);
  }
};
