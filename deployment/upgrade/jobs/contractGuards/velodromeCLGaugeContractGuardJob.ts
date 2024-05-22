import { HardhatRuntimeEnvironment } from "hardhat/types";
import { tryVerify } from "../../../deploymentHelpers";
import { IJob, IUpgradeConfig, IVersions } from "../../../types";

export const velodromeCLGaugeContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
) => {
  const ethers = hre.ethers;
  console.log("Will deploy VelodromeCLGaugeContractGuard");

  if (config.execute) {
    const VelodromeCLGaugeContractGuard = await ethers.getContractFactory("VelodromeCLGaugeContractGuard");
    const velodromeCLGaugeContractGuard = await VelodromeCLGaugeContractGuard.deploy();
    await velodromeCLGaugeContractGuard.deployed();
    const address = velodromeCLGaugeContractGuard.address;

    console.log("VelodromeCLGaugeContractGuard deployed at", address);

    await tryVerify(
      hre,
      address,
      "contracts/guards/contractGuards/velodrome/VelodromeCLGaugeContractGuard.sol:VelodromeCLGaugeContractGuard",
      [],
    );

    versions[config.newTag].contracts.VelodromeCLGaugeContractGuard = address;
  }
};
