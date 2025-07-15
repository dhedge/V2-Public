import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IJob, IUpgradeConfig, IVersions, IFileNames } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";

export const pancakeNonfungiblePositionGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  const pancakeNonfungiblePositionManagerAddress = addresses.pancakeswap?.nonfungiblePositionManager;
  const masterChefV3Address = addresses.pancakeswap?.masterChefV3;

  if (!pancakeNonfungiblePositionManagerAddress || !masterChefV3Address) {
    return console.warn("Pancakeswap addresses not configured: skipping.");
  }

  const nftTrackerAddress = versions[config.oldTag].contracts.DhedgeNftTrackerStorageProxy;

  if (!nftTrackerAddress) {
    return console.warn("nftTracker not deployed, skipping");
  }

  console.log("Will deploy PancakeNonfungiblePositionGuard");

  if (config.execute) {
    const ethers = hre.ethers;
    const PancakeNonfungiblePositionGuard = await ethers.getContractFactory("PancakeNonfungiblePositionGuard");
    const guard = await PancakeNonfungiblePositionGuard.deploy(nftTrackerAddress, masterChefV3Address);
    await guard.deployed();

    console.log("PancakeNonfungiblePositionGuard deployed at", guard.address);
    versions[config.newTag].contracts.PancakeNonfungiblePositionGuard = guard.address;

    await tryVerify(
      hre,
      guard.address,
      "contracts/guards/contractGuards/pancake/PancakeNonfungiblePositionGuard.sol:PancakeNonfungiblePositionGuard",
      [nftTrackerAddress, masterChefV3Address],
    );

    const Governance = await hre.artifacts.readArtifact("Governance");
    const setContractGuardABI = new ethers.utils.Interface(Governance.abi).encodeFunctionData("setContractGuard", [
      pancakeNonfungiblePositionManagerAddress,
      guard.address,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setContractGuardABI,
      "setContractGuard for PancakeNonfungiblePositionGuard",
      config,
      addresses,
    );

    await addOrReplaceGuardInFile(
      filenames.contractGuardsFileName,
      {
        contractAddress: pancakeNonfungiblePositionManagerAddress,
        guardName: "PancakeNonfungiblePositionGuard",
        guardAddress: guard.address,
        description: "Pancakeswap Concentrated Liquidity Position Manager Guard",
      },
      "contractAddress",
    );
  }
};
