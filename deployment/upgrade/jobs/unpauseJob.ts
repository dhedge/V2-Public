import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx } from "../../deploymentHelpers";
import { IJob, IProposeTxProperties, IUpgradeConfig, IVersions, IFileNames } from "../../types";

export const unpauseJob: IJob<void> = async (
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

  console.log("Will unpause");
  if (config.execute) {
    // Unpause Pool Factory
    const unpauseABI = PoolFactoryABI.encodeFunctionData("unpause", []);
    await proposeTx(poolFactoryProxy, unpauseABI, "Unpause pool Factory", config, addresses);
  }
};
