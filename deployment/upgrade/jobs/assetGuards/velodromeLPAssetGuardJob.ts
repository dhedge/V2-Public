import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";
import { AssetType } from "../assetsJob";
import { addOrReplaceGuardInFile } from "../helpers";

export const velodromeLPAssetGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  console.log("Will deploy velodromelpassetguard");
  if (!addresses.velodrome?.voter) {
    console.warn("Velodrome voter address not configured for VelodromeLPAssetGuard skipping.");
    return;
  }
  if (config.execute) {
    const ethers = hre.ethers;
    const Governance = await hre.artifacts.readArtifact("Governance");
    const governanceABI = new ethers.utils.Interface(Governance.abi);

    const VelodromeLPAssetGuard = await ethers.getContractFactory("VelodromeLPAssetGuard");
    const velodromeLPAssetGuard = await VelodromeLPAssetGuard.deploy(addresses.velodrome.voter);
    await velodromeLPAssetGuard.deployed();
    console.log("VelodromeLPAssetGuard deployed at", velodromeLPAssetGuard.address);

    versions[config.newTag].contracts.VelodromeLPAssetGuard = velodromeLPAssetGuard.address;

    await tryVerify(
      hre,
      velodromeLPAssetGuard.address,
      "contracts/guards/assetGuards/velodrome/VelodromeLPAssetGuard.sol:VelodromeLPAssetGuard",
      [addresses.velodrome.voter],
    );
    const assetHandlerAssetType = AssetType["Velodrome LP/Gauge Asset"];
    const setAssetGuardABI = governanceABI.encodeFunctionData("setAssetGuard", [
      assetHandlerAssetType,
      velodromeLPAssetGuard.address,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setAssetGuardABI,
      "setAssetGuard for VelodromeLPAssetGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      assetType: assetHandlerAssetType,
      guardName: "VelodromeLPAssetGuard",
      guardAddress: velodromeLPAssetGuard.address,
      description: "Velodrome LP + Gauge Positions",
    };

    await addOrReplaceGuardInFile(filenames.assetGuardsFileName, deployedGuard, "assetType");
  }
};
