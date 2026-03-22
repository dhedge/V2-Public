import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";
import { AssetType } from "../assetsJob";
import { addOrReplaceGuardInFile } from "../helpers";

export const virtualTokenAssetGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  console.log("Will deploy VirtualTokenAssetGuard");

  if (config.execute) {
    const ethers = hre.ethers;

    const VirtualTokenAssetGuard = await ethers.getContractFactory("VirtualTokenAssetGuard");
    const virtualTokenAssetGuard = await VirtualTokenAssetGuard.deploy();
    await virtualTokenAssetGuard.deployed();
    const virtualTokenAssetGuardAddress = virtualTokenAssetGuard.address;
    console.log("VirtualTokenAssetGuard deployed at", virtualTokenAssetGuardAddress);

    versions[config.newTag].contracts.VirtualTokenAssetGuard = virtualTokenAssetGuardAddress;

    await tryVerify(
      hre,
      virtualTokenAssetGuardAddress,
      "contracts/guards/assetGuards/VirtualTokenAssetGuard.sol:VirtualTokenAssetGuard",
      [],
    );

    const Governance = await hre.artifacts.readArtifact("Governance");
    const assetHandlerAssetType = AssetType["Virtual Token Asset"];
    const setAssetGuardTxData = new ethers.utils.Interface(Governance.abi).encodeFunctionData("setAssetGuard", [
      assetHandlerAssetType,
      virtualTokenAssetGuardAddress,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setAssetGuardTxData,
      "setAssetGuard for VirtualTokenAssetGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      assetType: assetHandlerAssetType,
      guardName: "VirtualTokenAssetGuard",
      guardAddress: virtualTokenAssetGuardAddress,
      description: "Virtual Token Asset Guard",
    };

    await addOrReplaceGuardInFile(filenames.assetGuardsFileName, deployedGuard, "assetType");
  }
};
