import { HardhatRuntimeEnvironment } from "hardhat/types";
import { tryVerify } from "../../../deploymentHelpers";
import { IJob, IUpgradeConfig, IVersions } from "../../../types";

export const ramsesGaugeGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
) => {
  console.log("Will deploy RamsesGaugeContractGuard");

  if (config.execute) {
    const ethers = hre.ethers;

    const RamsesGaugeContractGuard = await ethers.getContractFactory("RamsesGaugeContractGuard");
    const ramsesGaugeContractGuard = await RamsesGaugeContractGuard.deploy();
    await ramsesGaugeContractGuard.deployed();
    const ramsesGaugeContractGuardAddress = ramsesGaugeContractGuard.address;
    console.log("RamsesGaugeContractGuard deployed at", ramsesGaugeContractGuardAddress);

    versions[config.newTag].contracts.RamsesGaugeContractGuard = ramsesGaugeContractGuardAddress;

    await tryVerify(
      hre,
      ramsesGaugeContractGuardAddress,
      "contracts/guards/contractGuards/ramses/RamsesGaugeContractGuard.sol:RamsesGaugeContractGuard",
      [],
    );
  }
};
