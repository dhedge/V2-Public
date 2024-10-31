import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IJob, IUpgradeConfig, IVersions, IFileNames } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";

export const velodromeNonfungiblePositionGuardOldJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  const velodromeCLNonfungiblePositionManagerOldAddress = addresses.velodromeCL?.nonfungiblePositionManagerOld;

  if (!velodromeCLNonfungiblePositionManagerOldAddress) {
    return console.warn(
      "velodromeCLNonfungiblePositionManagerOldAddress not configured for VelodromeNonfungiblePositionGuardOld: skipping.",
    );
  }

  const nftTrackerAddress = versions[config.oldTag].contracts.DhedgeNftTrackerStorageProxy;
  if (!nftTrackerAddress) {
    return console.warn("nftTracker not deployed, skipping");
  }

  console.log("Will deploy VelodromeNonfungiblePositionGuardOld");
  if (config.execute) {
    const ethers = hre.ethers;
    const Governance = await hre.artifacts.readArtifact("Governance");
    const governanceABI = new ethers.utils.Interface(Governance.abi);
    const VelodromeNonfungiblePositionGuardOld = await ethers.getContractFactory(
      "VelodromeNonfungiblePositionGuardOld",
    );
    const velodromeNonfungiblePositionGuard = await VelodromeNonfungiblePositionGuardOld.deploy(nftTrackerAddress);
    await velodromeNonfungiblePositionGuard.deployed();
    const velodromeNonfungiblePositionGuardOldAddress = velodromeNonfungiblePositionGuard.address;

    console.log("VelodromeNonfungiblePositionGuardOld deployed at", velodromeNonfungiblePositionGuardOldAddress);
    versions[config.newTag].contracts.VelodromeNonfungiblePositionGuardOld =
      velodromeNonfungiblePositionGuardOldAddress;

    await tryVerify(
      hre,
      velodromeNonfungiblePositionGuardOldAddress,
      "contracts/guards/contractGuards/velodrome/VelodromeNonfungiblePositionGuardOld.sol:VelodromeNonfungiblePositionGuardOld",
      [nftTrackerAddress],
    );

    const setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
      velodromeCLNonfungiblePositionManagerOldAddress,
      velodromeNonfungiblePositionGuardOldAddress,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setContractGuardABI,
      "setContractGuard for VelodromeNonfungiblePositionGuardOld",
      config,
      addresses,
    );

    const deployedGuard = {
      contractAddress: velodromeCLNonfungiblePositionManagerOldAddress,
      guardName: "VelodromeNonfungiblePositionGuardOld",
      guardAddress: velodromeNonfungiblePositionGuardOldAddress,
      description: "VelodromeCL Nonfungible Position Old contract",
    };

    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
  }
};
