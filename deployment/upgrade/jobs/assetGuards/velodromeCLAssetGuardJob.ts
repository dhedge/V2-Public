import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IJob, IProposeTxProperties, IUpgradeConfig, IVersions, IFileNames } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";
import { AssetType } from "../assetsJob";

export const velodromeCLAssetGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IProposeTxProperties,
) => {
  console.log("Will deploy VelodromeCLAssetGuard");
  if (config.execute) {
    const ethers = hre.ethers;
    const Governance = await hre.artifacts.readArtifact("Governance");
    const governanceABI = new ethers.utils.Interface(Governance.abi);

    const VelodromeCLAssetGuard = await ethers.getContractFactory("VelodromeCLAssetGuard");
    const velodromeCLAssetGuard = await VelodromeCLAssetGuard.deploy();
    await velodromeCLAssetGuard.deployed();
    const velodromeCLAssetGuardAddress = velodromeCLAssetGuard.address;
    console.log("VelodromeCLAssetGuard deployed at", velodromeCLAssetGuardAddress);

    versions[config.newTag].contracts.VelodromeCLAssetGuard = velodromeCLAssetGuardAddress;

    await tryVerify(
      hre,
      velodromeCLAssetGuardAddress,
      "contracts/guards/assetGuards/velodrome/VelodromeCLAssetGuard.sol:VelodromeCLAssetGuard",
      [],
    );
    const assetHandlerAssetType = AssetType["Velodrome CL NFT Position Asset"];
    const setAssetGuardABI = governanceABI.encodeFunctionData("setAssetGuard", [
      assetHandlerAssetType,
      velodromeCLAssetGuardAddress,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setAssetGuardABI,
      "setAssetGuard for VelodromeCLAssetGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      assetType: assetHandlerAssetType,
      guardName: "VelodromeCLAssetGuard",
      guardAddress: velodromeCLAssetGuardAddress,
      description: "VelodromeCL LP positions",
    };

    await addOrReplaceGuardInFile(filenames.assetGuardsFileName, deployedGuard, "assetType");
  }
};
