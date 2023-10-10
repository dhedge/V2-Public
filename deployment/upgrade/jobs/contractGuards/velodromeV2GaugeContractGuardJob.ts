import { HardhatRuntimeEnvironment } from "hardhat/types";
import { tryVerify } from "../../../deploymentHelpers";
import { IJob, IUpgradeConfig, IVersions } from "../../../types";

export const velodromeV2GaugeContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
) => {
  const ethers = hre.ethers;
  console.log("Will deploy VelodromeV2GaugeContractGuard");

  if (config.execute) {
    const VelodromeV2GaugeContractGuard = await ethers.getContractFactory("VelodromeV2GaugeContractGuard");
    const velodromeV2GaugeContractGuard = await VelodromeV2GaugeContractGuard.deploy();
    await velodromeV2GaugeContractGuard.deployed();
    const address = velodromeV2GaugeContractGuard.address;

    console.log("VelodromeV2GaugeContractGuard deployed at", address);

    await tryVerify(
      hre,
      address,
      "contracts/guards/contractGuards/velodrome/VelodromeV2GaugeContractGuard.sol:VelodromeV2GaugeContractGuard",
      [],
    );

    versions[config.newTag].contracts.VelodromeV2GaugeContractGuard = address;
  }
};
