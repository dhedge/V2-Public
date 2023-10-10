import { HardhatRuntimeEnvironment } from "hardhat/types";
import { tryVerify } from "../../../deploymentHelpers";
import { Address, IJob, IUpgradeConfig, IVersions } from "../../../types";

/***
 * Deploys the MaiVaultContractGuard
 */
export const maiVaultContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
) => {
  const ethers = hre.ethers;

  const nftTrackerAddress = versions[config.oldTag].contracts.DhedgeNftTrackerStorageProxy;
  if (!nftTrackerAddress) {
    console.warn("nftTracker not deployed for MaiVaultContractGuard, skipping");
    return;
  }

  console.log("Will deploy maivaultcontractguard");
  if (config.execute) {
    const ContractGuard = await ethers.getContractFactory("MaiVaultContractGuard");
    const args: [Address] = [nftTrackerAddress];
    const contractGuard = await ContractGuard.deploy(...args);
    await contractGuard.deployed();
    await contractGuard.deployTransaction.wait(5);
    console.log("contract guard deployed at", contractGuard.address);

    await tryVerify(
      hre,
      contractGuard.address,
      "contracts/guards/contractGuards/MaiVaultContractGuard.sol:MaiVaultContractGuard",
      [args],
    );
    versions[config.newTag].contracts.MaiVaultContractGuard = contractGuard.address;
  }
};
