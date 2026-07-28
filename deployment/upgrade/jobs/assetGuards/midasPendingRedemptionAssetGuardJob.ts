import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IJob, IAddresses, IUpgradeConfig, IVersions, IFileNames } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";
import { AssetType } from "../assetsJob";

// Asset type 43 (keyed by the Midas redemption vault address). Stateless — no constructor args; it
// resolves request tracking and the pool whitelist through the redemption vault's contract guard.
export const midasPendingRedemptionAssetGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  if (!addresses.midas) {
    return console.warn("midas config not set: skipping midasPendingRedemptionAssetGuardJob.");
  }

  console.log("Will deploy MidasPendingRedemptionAssetGuard");

  if (config.execute) {
    const ethers = hre.ethers;
    const MidasPendingRedemptionAssetGuard = await ethers.getContractFactory("MidasPendingRedemptionAssetGuard");

    const midasPendingRedemptionAssetGuard = await MidasPendingRedemptionAssetGuard.deploy();
    await midasPendingRedemptionAssetGuard.deployed();
    const guardAddress = midasPendingRedemptionAssetGuard.address;

    console.log("MidasPendingRedemptionAssetGuard deployed at", guardAddress);
    versions[config.newTag].contracts.MidasPendingRedemptionAssetGuard = guardAddress;

    await tryVerify(
      hre,
      guardAddress,
      "contracts/guards/assetGuards/midas/MidasPendingRedemptionAssetGuard.sol:MidasPendingRedemptionAssetGuard",
      [],
    );

    const Governance = await hre.artifacts.readArtifact("Governance");
    const assetType = AssetType["Midas Pending Redemption Asset"];
    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      new ethers.utils.Interface(Governance.abi).encodeFunctionData("setAssetGuard", [assetType, guardAddress]),
      "setAssetGuard for MidasPendingRedemptionAssetGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      assetType,
      guardName: "MidasPendingRedemptionAssetGuard",
      guardAddress,
      description: "Midas Pending Redemption Asset",
    };
    await addOrReplaceGuardInFile(filenames.assetGuardsFileName, deployedGuard, "assetType");
  }
};
