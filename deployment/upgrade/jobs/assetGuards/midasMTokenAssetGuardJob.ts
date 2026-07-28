import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IJob, IAddresses, IUpgradeConfig, IVersions, IFileNames } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";
import { AssetType } from "../assetsJob";

// Asset type 42. Deploy AFTER midasRedemptionVaultContractGuardJob: the guard derives each served
// mToken from its redemption vault and resolves the pool whitelist through that vault's contract
// guard, which must already be registered in Governance.
export const midasMTokenAssetGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  if (!addresses.midas) {
    return console.warn("midas config not set: skipping midasMTokenAssetGuardJob.");
  }

  console.log("Will deploy MidasMTokenAssetGuard");

  if (config.execute) {
    const ethers = hre.ethers;
    const MidasMTokenAssetGuard = await ethers.getContractFactory("MidasMTokenAssetGuard");

    // One redemption vault per served mToken; the guard derives the mToken from each vault.
    const redemptionVaults = [addresses.midas.redemptionVault];
    const midasMTokenAssetGuard = await MidasMTokenAssetGuard.deploy(redemptionVaults);
    await midasMTokenAssetGuard.deployed();
    const guardAddress = midasMTokenAssetGuard.address;

    console.log("MidasMTokenAssetGuard deployed at", guardAddress);
    versions[config.newTag].contracts.MidasMTokenAssetGuard = guardAddress;

    await tryVerify(
      hre,
      guardAddress,
      "contracts/guards/assetGuards/midas/MidasMTokenAssetGuard.sol:MidasMTokenAssetGuard",
      [redemptionVaults],
    );

    const Governance = await hre.artifacts.readArtifact("Governance");
    const assetType = AssetType["Midas mToken Asset"];
    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      new ethers.utils.Interface(Governance.abi).encodeFunctionData("setAssetGuard", [assetType, guardAddress]),
      "setAssetGuard for MidasMTokenAssetGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      assetType,
      guardName: "MidasMTokenAssetGuard",
      guardAddress,
      description: "Midas mToken Asset",
    };
    await addOrReplaceGuardInFile(filenames.assetGuardsFileName, deployedGuard, "assetType");
  }
};
