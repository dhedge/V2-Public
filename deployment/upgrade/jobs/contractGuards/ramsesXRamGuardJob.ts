import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";

export const ramsesXRamGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  console.log("Will deploy RamsesXRamContractGuard");
  const xRam = addresses.ramses?.xRam;

  if (!xRam) {
    return console.warn("xRam address not configured for RamsesXRamContractGuard. skipping.");
  }

  if (config.execute) {
    const ethers = hre.ethers;

    const RamsesXRamContractGuard = await ethers.getContractFactory("RamsesXRamContractGuard");
    const ramsesXRamContractGuard = await RamsesXRamContractGuard.deploy();
    await ramsesXRamContractGuard.deployed();
    const ramsesXRamContractGuardAddress = ramsesXRamContractGuard.address;
    console.log("RamsesXRamContractGuard deployed at", ramsesXRamContractGuardAddress);

    versions[config.newTag].contracts.RamsesXRamContractGuard = ramsesXRamContractGuardAddress;

    await tryVerify(
      hre,
      ramsesXRamContractGuardAddress,
      "contracts/guards/contractGuards/ramses/RamsesXRamContractGuard.sol:RamsesXRamContractGuard",
      [],
    );

    const Governance = await hre.artifacts.readArtifact("Governance");
    const governanceABI = new ethers.utils.Interface(Governance.abi);
    const setContractGuardTxData = governanceABI.encodeFunctionData("setContractGuard", [
      xRam,
      ramsesXRamContractGuardAddress,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setContractGuardTxData,
      "setContractGuard for RamsesXRamContractGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      contractAddress: xRam,
      guardName: "RamsesXRamContractGuard",
      guardAddress: ramsesXRamContractGuardAddress,
      description: "Ramses XRam Guard",
    };

    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
  }
};
