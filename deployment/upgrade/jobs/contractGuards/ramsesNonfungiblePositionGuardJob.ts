import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IJob, IUpgradeConfig, IVersions, IFileNames } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";

const MAX_NUMBER_LP_POSITIONS = 1;

export const ramsesNonfungiblePositionGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  const ramsesCLNonfungiblePositionManagerAddress = addresses.ramsesCL?.nonfungiblePositionManager;

  if (!ramsesCLNonfungiblePositionManagerAddress) {
    return console.warn(
      "ramses NonfungiblePositionManager address not configured for ramsesNonfungiblePositionGuard: skipping.",
    );
  }

  const nftTrackerAddress = versions[config.oldTag].contracts.DhedgeNftTrackerStorageProxy;
  if (!nftTrackerAddress) {
    console.warn("nftTracker not deployed, skipping");
    return;
  }

  console.log("Will deploy RamsesNonfungiblePositionGuard");
  if (config.execute) {
    const ethers = hre.ethers;
    const Governance = await hre.artifacts.readArtifact("Governance");
    const governanceABI = new ethers.utils.Interface(Governance.abi);
    const RamsesNonfungiblePositionGuard = await ethers.getContractFactory("RamsesNonfungiblePositionGuard");
    const ramsesNonfungiblePositionGuard = await RamsesNonfungiblePositionGuard.deploy(
      MAX_NUMBER_LP_POSITIONS,
      nftTrackerAddress,
    );
    await ramsesNonfungiblePositionGuard.deployed();
    const ramsesNonfungiblePositionGuardAddress = ramsesNonfungiblePositionGuard.address;

    console.log("RamsesNonfungiblePositionGuard deployed at", ramsesNonfungiblePositionGuardAddress);
    versions[config.newTag].contracts.RamsesNonfungiblePositionGuard = ramsesNonfungiblePositionGuardAddress;

    await tryVerify(
      hre,
      ramsesNonfungiblePositionGuardAddress,
      "contracts/guards/contractGuards/ramsesCL/RamsesNonfungiblePositionGuard.sol:RamsesNonfungiblePositionGuard",
      [MAX_NUMBER_LP_POSITIONS, nftTrackerAddress],
    );

    const setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
      ramsesCLNonfungiblePositionManagerAddress,
      ramsesNonfungiblePositionGuardAddress,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setContractGuardABI,
      "setContractGuard for RamsesNonfungiblePositionGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      contractAddress: ramsesCLNonfungiblePositionManagerAddress,
      guardName: "RamsesNonfungiblePositionGuard",
      guardAddress: ramsesNonfungiblePositionGuardAddress,
      description: "RamsesCL Nonfungible Position contract",
    };

    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
  }
};
