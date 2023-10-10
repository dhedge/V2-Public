import { HardhatRuntimeEnvironment } from "hardhat/types";
import { tryVerify } from "../../../deploymentHelpers";
import { IJob, IUpgradeConfig, IVersions } from "../../../types";

export const velodromePairContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
) => {
  console.log("Will deploy VelodromePairContractGuard");

  if (config.execute) {
    const VelodromePairContractGuard = await hre.ethers.getContractFactory("VelodromePairContractGuard");
    const velodromePairContractGuard = await VelodromePairContractGuard.deploy();
    await velodromePairContractGuard.deployed();
    const address = velodromePairContractGuard.address;

    console.log("VelodromePairContractGuard deployed at", address);

    await tryVerify(
      hre,
      address,
      "contracts/guards/contractGuards/velodrome/VelodromePairContractGuard.sol:VelodromePairContractGuard",
      [],
    );

    versions[config.newTag].contracts.VelodromePairContractGuard = address;
  }
};
