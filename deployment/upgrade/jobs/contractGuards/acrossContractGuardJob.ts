import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";

export const acrossContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  console.log("Will deploy AcrossContractGuard");
  const spokePool = addresses.across?.spokePool;

  if (!spokePool) return console.warn("SpokePool address not configured for AcrossContractGuard. Skipping.");

  const approvedDestinations = addresses.across?.approvedDestinations;

  if (!approvedDestinations || approvedDestinations.length === 0) {
    return console.warn("Approved destinations not configured for AcrossContractGuard. Skipping.");
  }

  if (config.execute) {
    const ethers = hre.ethers;

    const AcrossContractGuard = await ethers.getContractFactory("AcrossContractGuard");
    const args: Parameters<typeof AcrossContractGuard.deploy> = [approvedDestinations];
    const acrossContractGuard = await AcrossContractGuard.deploy(...args);
    await acrossContractGuard.deployed();
    const acrossContractGuardAddress = acrossContractGuard.address;
    console.log("AcrossContractGuard deployed at", acrossContractGuardAddress);

    versions[config.newTag].contracts.AcrossContractGuard = acrossContractGuardAddress;

    await tryVerify(
      hre,
      acrossContractGuardAddress,
      "contracts/guards/contractGuards/across/AcrossContractGuard.sol:AcrossContractGuard",
      args,
    );

    const Governance = await hre.artifacts.readArtifact("Governance");
    const setContractGuardTxData = new ethers.utils.Interface(Governance.abi).encodeFunctionData("setContractGuard", [
      spokePool,
      acrossContractGuardAddress,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setContractGuardTxData,
      "setContractGuard for AcrossContractGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      contractAddress: spokePool,
      guardName: "AcrossContractGuard",
      guardAddress: acrossContractGuardAddress,
      description: "Across Contract Guard",
    };

    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
  }
};
