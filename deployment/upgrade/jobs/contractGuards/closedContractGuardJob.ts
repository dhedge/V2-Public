import { HardhatRuntimeEnvironment } from "hardhat/types";
import { tryVerify } from "../../../deploymentHelpers";
import { IJob, IUpgradeConfig, IVersions } from "../../../types";

export const closedContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
) => {
  console.log("Will deploy ClosedContractGuard");

  if (config.execute) {
    const ClosedContractGuard = await hre.ethers.getContractFactory("ClosedContractGuard");
    const closedContractGuard = await ClosedContractGuard.deploy();
    await closedContractGuard.deployed();
    const closedContractGuardAddress = closedContractGuard.address;

    console.log("ClosedContractGuard deployed at", closedContractGuardAddress);

    versions[config.newTag].contracts.ClosedContractGuard = closedContractGuardAddress;

    await tryVerify(
      hre,
      closedContractGuardAddress,
      "contracts/guards/contractGuards/ClosedContractGuard.sol:ClosedContractGuard",
      [],
    );
  }
};
