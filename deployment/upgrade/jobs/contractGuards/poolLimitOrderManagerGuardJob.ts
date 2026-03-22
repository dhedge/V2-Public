import { HardhatRuntimeEnvironment } from "hardhat/types";

import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IDeployedContractGuard, IJob, IUpgradeConfig, IVersions, IFileNames, IAddresses } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";

export const poolLimitOrderManagerGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  const poolLimitOrderManagerProxy = versions[config.newTag].contracts.PoolLimitOrderManagerProxy;
  if (!poolLimitOrderManagerProxy) return console.warn("PoolLimitOrderManagerProxy could not be found: skipping.");

  console.log("Will deploy PoolLimitOrderManagerGuard");

  if (config.execute) {
    const ethers = hre.ethers;
    const PoolLimitOrderManagerGuard = await ethers.getContractFactory("PoolLimitOrderManagerGuard");
    const args: Parameters<typeof PoolLimitOrderManagerGuard.deploy> = [];
    const poolLimitOrderManagerGuard = await PoolLimitOrderManagerGuard.deploy(...args);
    await poolLimitOrderManagerGuard.deployed();
    const poolLimitOrderManagerGuardAddress = poolLimitOrderManagerGuard.address;

    console.log("PoolLimitOrderManagerGuard deployed at: ", poolLimitOrderManagerGuardAddress);

    versions[config.newTag].contracts.PoolLimitOrderManagerGuard = poolLimitOrderManagerGuardAddress;

    await tryVerify(
      hre,
      poolLimitOrderManagerGuardAddress,
      "contracts/guards/contractGuards/PoolLimitOrderManagerGuard.sol:PoolLimitOrderManagerGuard",
      args,
    );

    const Governance = await hre.artifacts.readArtifact("Governance");
    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      new ethers.utils.Interface(Governance.abi).encodeFunctionData("setContractGuard", [
        poolLimitOrderManagerProxy,
        poolLimitOrderManagerGuardAddress,
      ]),
      "setContractGuard for PoolLimitOrderManager",
      config,
      addresses,
    );

    const deployedGuard: IDeployedContractGuard = {
      contractAddress: poolLimitOrderManagerProxy,
      guardName: "PoolLimitOrderManagerGuard",
      guardAddress: poolLimitOrderManagerGuardAddress,
      description: "PoolLimitOrderManager - allows setting limit orders on Toros vaults",
    };
    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
  }
};
