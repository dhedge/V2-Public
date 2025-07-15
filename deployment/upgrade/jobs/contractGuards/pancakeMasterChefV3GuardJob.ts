import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IJob, IUpgradeConfig, IVersions, IFileNames } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";

export const pancakeMasterChefV3GuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  const masterChefV3Address = addresses.pancakeswap?.masterChefV3;

  if (!masterChefV3Address) {
    return console.warn("Pancakeswap MasterChefV3 address not configured: skipping.");
  }

  const nftTrackerAddress = versions[config.oldTag].contracts.DhedgeNftTrackerStorageProxy;

  if (!nftTrackerAddress) {
    return console.warn("nftTracker not deployed, skipping");
  }

  console.log("Will deploy PancakeMasterChefV3Guard");

  if (config.execute) {
    const ethers = hre.ethers;
    const PancakeMasterChefV3Guard = await ethers.getContractFactory("PancakeMasterChefV3Guard");
    const guard = await PancakeMasterChefV3Guard.deploy(nftTrackerAddress);
    await guard.deployed();

    console.log("PancakeMasterChefV3Guard deployed at", guard.address);
    versions[config.newTag].contracts.PancakeMasterChefV3Guard = guard.address;

    await tryVerify(
      hre,
      guard.address,
      "contracts/guards/contractGuards/pancake/PancakeMasterChefV3Guard.sol:PancakeMasterChefV3Guard",
      [nftTrackerAddress],
    );

    const Governance = await hre.artifacts.readArtifact("Governance");
    const setContractGuardABI = new ethers.utils.Interface(Governance.abi).encodeFunctionData("setContractGuard", [
      masterChefV3Address,
      guard.address,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setContractGuardABI,
      "setContractGuard for PancakeMasterChefV3Guard",
      config,
      addresses,
    );

    await addOrReplaceGuardInFile(
      filenames.contractGuardsFileName,
      {
        contractAddress: masterChefV3Address,
        guardName: "PancakeMasterChefV3Guard",
        guardAddress: guard.address,
        description: "Pancakeswap MasterChefV3 staking contract guard",
      },
      "contractAddress",
    );
  }
};
