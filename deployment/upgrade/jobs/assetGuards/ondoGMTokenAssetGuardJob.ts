import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IJob, IAddresses, IUpgradeConfig, IVersions, IFileNames, Address } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";
import { AssetType } from "../assetsJob";

export const ondoGMTokenAssetGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  if (!addresses.ondo?.ondoGMTokenAssetGuard) {
    return console.warn("ondo.ondoGMTokenAssetGuard config not set: skipping.");
  }
  if (!addresses.assets?.usdc) {
    return console.warn("assets.usdc not configured: skipping.");
  }

  const ondoGMSwapProxy =
    versions[config.newTag].contracts.OndoGMSwapProxy ?? versions[config.oldTag].contracts.OndoGMSwapProxy;
  if (!ondoGMSwapProxy) {
    return console.warn("OndoGMSwapProxy not found in versions: skipping.");
  }

  console.log("Will deploy OndoGMTokenAssetGuard");

  if (config.execute) {
    const ethers = hre.ethers;
    const OndoGMTokenAssetGuard = await ethers.getContractFactory("OndoGMTokenAssetGuard");

    const args: [Address, number, string] = [
      ondoGMSwapProxy,
      addresses.ondo.ondoGMTokenAssetGuard.mismatchDeltaNumerator,
      addresses.ondo.ondoGMTokenAssetGuard.minRedeemValue,
    ];
    const ondoGMTokenAssetGuard = await OndoGMTokenAssetGuard.deploy(...args);
    await ondoGMTokenAssetGuard.deployed();
    const guardAddress = ondoGMTokenAssetGuard.address;

    console.log("OndoGMTokenAssetGuard deployed at", guardAddress);
    versions[config.newTag].contracts.OndoGMTokenAssetGuard = guardAddress;

    await tryVerify(
      hre,
      guardAddress,
      "contracts/guards/assetGuards/ondo/OndoGMTokenAssetGuard.sol:OndoGMTokenAssetGuard",
      args,
    );

    const Governance = await hre.artifacts.readArtifact("Governance");
    const assetType = AssetType["Ondo GM Token Asset"];
    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      new ethers.utils.Interface(Governance.abi).encodeFunctionData("setAssetGuard", [assetType, guardAddress]),
      "setAssetGuard for OndoGMTokenAssetGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      assetType,
      guardName: "OndoGMTokenAssetGuard",
      guardAddress,
      description: "Ondo GM Token Asset",
    };

    await addOrReplaceGuardInFile(filenames.assetGuardsFileName, deployedGuard, "assetType");
  }
};
