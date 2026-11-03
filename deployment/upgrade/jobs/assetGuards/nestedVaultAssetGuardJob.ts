import fs from "fs";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx } from "../../../helpers/safe";
import { tryVerify } from "../../../helpers/verify";
import { addOrReplaceGuardInFile } from "../../../helpers/csv";
import { IJob, IProposeTxProperties, IUpgradeConfig, IVersions, IFileNames } from "../../../types";
import { AssetType } from "../assetsJob";
import { TAssetConfig } from "../oracles/oracleTypes";

/// Deploys NestedVaultAssetGuard and proposes setAssetGuard for type 1. Run it, and the
/// `withdrawalvault` job, before the `assets` job re-types the nested vaults: an asset whose type has
/// no guard cannot be priced or withdrawn, and a WithdrawalVault without the type reverts on unroll.
export const nestedVaultAssetGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IProposeTxProperties,
) => {
  const assetType = AssetType["Nested Vault Asset"];
  const assets: TAssetConfig[] = JSON.parse(fs.readFileSync(filenames.assetsFileName, "utf-8"));
  if (!assets.some((asset) => Number(asset.assetType) === assetType)) {
    throw new Error(`No asset of type ${assetType} in ${filenames.assetsFileName}; nothing to guard on this chain`);
  }

  const ethers = hre.ethers;
  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);

  console.log("Will deploy NestedVaultAssetGuard");

  if (config.execute) {
    const NestedVaultAssetGuard = await ethers.getContractFactory("NestedVaultAssetGuard");
    const guard = await NestedVaultAssetGuard.deploy();
    await guard.deployed();
    const guardAddress = guard.address;
    console.log("NestedVaultAssetGuard deployed at", guardAddress);
    versions[config.newTag].contracts.NestedVaultAssetGuard = guardAddress;
    await tryVerify(
      hre,
      guardAddress,
      "contracts/guards/assetGuards/NestedVaultAssetGuard.sol:NestedVaultAssetGuard",
      [],
    );

    console.log(`Setting NestedVaultAssetGuard for assetType ${assetType}`);
    const setAssetGuardTxData = governanceABI.encodeFunctionData("setAssetGuard", [assetType, guardAddress]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setAssetGuardTxData,
      `setAssetGuard for NestedVaultAssetGuard AssetType ${assetType}`,
      config,
      addresses,
    );

    const deployedGuard = {
      assetType,
      guardName: "NestedVaultAssetGuard",
      guardAddress,
      description: "Nested Vault Asset",
    };

    await addOrReplaceGuardInFile(filenames.assetGuardsFileName, deployedGuard, "assetType");
  }
};
