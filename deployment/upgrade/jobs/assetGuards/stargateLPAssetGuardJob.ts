import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";
import { AssetType } from "../assetsJob";
import { addOrReplaceGuardInFile } from "../helpers";

export const stargateLPAssetGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  console.log("Will deploy stargatelpassetguard");

  if (!addresses.stargate.staking) {
    console.warn("stargate.staking not configured for stargateLPAssetGuard: skipping.");
    return;
  }

  if (config.execute) {
    const ethers = hre.ethers;
    const Governance = await hre.artifacts.readArtifact("Governance");
    const governanceABI = new ethers.utils.Interface(Governance.abi);
    const args: [string] = [addresses.stargate.staking];
    const StargateLPAssetGuard = await ethers.getContractFactory("StargateLPAssetGuard");
    const stargateLPAssetGuard = await StargateLPAssetGuard.deploy(...args);
    await stargateLPAssetGuard.deployed();
    console.log("StargateLPAssetGuard deployed at", stargateLPAssetGuard.address);

    versions[config.newTag].contracts.StargateLPAssetGuard = stargateLPAssetGuard.address;

    await tryVerify(
      hre,
      stargateLPAssetGuard.address,
      "contracts/guards/assetGuards/StargateLPAssetGuard.sol:StargateLPAssetGuard",
      args,
    );
    const assetHandlerAssetType = AssetType["Stargate Lp"];
    const setAssetGuardABI = governanceABI.encodeFunctionData("setAssetGuard", [
      assetHandlerAssetType,
      stargateLPAssetGuard.address,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setAssetGuardABI,
      "setAssetGuard for StargateLPAssetGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      assetType: assetHandlerAssetType,
      guardName: "StargateLPAssetGuard",
      guardAddress: stargateLPAssetGuard.address,
      description: "Stargate LP Asset Guard",
    };

    await addOrReplaceGuardInFile(filenames.assetGuardsFileName, deployedGuard, "assetType");
  }
};
