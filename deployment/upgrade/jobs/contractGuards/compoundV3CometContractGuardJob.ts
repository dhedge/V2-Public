import { HardhatRuntimeEnvironment } from "hardhat/types";
import { tryVerify } from "../../../deploymentHelpers";
import { IJob, IUpgradeConfig, IVersions } from "../../../types";

export const compoundV3CometContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
) => {
  if (config.execute) {
    const ethers = hre.ethers;

    const CompoundV3CometContractGuard = await ethers.getContractFactory("CompoundV3CometContractGuard");
    const compoundV3CometContractGuard = await CompoundV3CometContractGuard.deploy();
    await compoundV3CometContractGuard.deployed();
    const compoundV3CometContractGuardAddress = compoundV3CometContractGuard.address;
    console.log("CompoundV3CometContractGuard deployed at", compoundV3CometContractGuardAddress);

    versions[config.newTag].contracts.CompoundV3CometContractGuard = compoundV3CometContractGuardAddress;

    await tryVerify(
      hre,
      compoundV3CometContractGuardAddress,
      "contracts/guards/contractGuards/compound/CompoundV3CometContractGuard.sol:CompoundV3CometContractGuard",
      [],
    );
  }
};
