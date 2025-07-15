import { HardhatRuntimeEnvironment } from "hardhat/types";
import { tryVerify } from "../../../deploymentHelpers";
import { IJob, IUpgradeConfig, IVersions } from "../../../types";

export const fluidTokenContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
) => {
  console.log("Will deploy FluidTokenContractGuard");

  if (config.execute) {
    const FluidTokenContractGuard = await hre.ethers.getContractFactory("FluidTokenContractGuard");
    const fluidTokenContractGuard = await FluidTokenContractGuard.deploy();
    await fluidTokenContractGuard.deployed();
    const address = fluidTokenContractGuard.address;

    console.log("FluidTokenContractGuard deployed at", address);

    await tryVerify(
      hre,
      address,
      "contracts/guards/contractGuards/fluid/FluidTokenContractGuard.sol:FluidTokenContractGuard",
      [],
    );

    versions[config.newTag].contracts.FluidTokenContractGuard = address;
  }
};
