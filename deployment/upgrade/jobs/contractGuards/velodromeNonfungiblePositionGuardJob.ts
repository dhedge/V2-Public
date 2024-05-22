import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IJob, IUpgradeConfig, IVersions, IFileNames } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";

const MAX_NUMBER_LP_POSITIONS = 3;

export const velodromeNonfungiblePositionGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  const velodromeCLNonfungiblePositionManagerAddress = addresses.velodromeCL?.nonfungiblePositionManager;

  if (!velodromeCLNonfungiblePositionManagerAddress) {
    return console.warn(
      "velodromeCL NonfungiblePositionManager address not configured for VelodromeNonfungiblePositionGuard: skipping.",
    );
  }

  const nftTrackerAddress = versions[config.oldTag].contracts.DhedgeNftTrackerStorageProxy;
  if (!nftTrackerAddress) {
    console.warn("nftTracker not deployed, skipping");
    return;
  }

  console.log("Will deploy VelodromeNonfungiblePositionGuard");
  if (config.execute) {
    const ethers = hre.ethers;
    const Governance = await hre.artifacts.readArtifact("Governance");
    const governanceABI = new ethers.utils.Interface(Governance.abi);
    const VelodromeNonfungiblePositionGuard = await ethers.getContractFactory("VelodromeNonfungiblePositionGuard");
    const velodromeNonfungiblePositionGuard = await VelodromeNonfungiblePositionGuard.deploy(
      MAX_NUMBER_LP_POSITIONS,
      nftTrackerAddress,
    );
    await velodromeNonfungiblePositionGuard.deployed();
    const velodromeNonfungiblePositionGuardAddress = velodromeNonfungiblePositionGuard.address;

    console.log("VelodromeNonfungiblePositionGuard deployed at", velodromeNonfungiblePositionGuardAddress);
    versions[config.newTag].contracts.VelodromeNonfungiblePositionGuard = velodromeNonfungiblePositionGuardAddress;

    await tryVerify(
      hre,
      velodromeNonfungiblePositionGuardAddress,
      "contracts/guards/contractGuards/velodrome/VelodromeNonfungiblePositionGuard.sol:VelodromeNonfungiblePositionGuard",
      [MAX_NUMBER_LP_POSITIONS, nftTrackerAddress],
    );

    const setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
      velodromeCLNonfungiblePositionManagerAddress,
      velodromeNonfungiblePositionGuardAddress,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setContractGuardABI,
      "setContractGuard for VelodromeNonfungiblePositionGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      contractAddress: velodromeCLNonfungiblePositionManagerAddress,
      guardName: "VelodromeNonfungiblePositionGuard",
      guardAddress: velodromeNonfungiblePositionGuardAddress,
      description: "VelodromeCL Nonfungible Position contract",
    };

    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
  }
};
