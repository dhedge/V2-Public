import fs from "fs";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { executeInSeries, proposeTx } from "../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions, TDeployedAsset } from "../../types";
import { TAssetConfig } from "./oracles/oracleTypes";

export const removeAssetsJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  console.log("Running Remove Assets Job");
  const ethers = hre.ethers;

  const filename = filenames.assetsFileName;

  const poolFactory = await ethers.getContractAt("PoolFactory", versions[config.newTag].contracts.PoolFactoryProxy);
  const jsonAssets: TAssetConfig[] = JSON.parse(fs.readFileSync(filename, "utf-8"));
  const assetAddressesToRemove: string[] = [];

  const assetsRemovedFromJson: TDeployedAsset[] = [];

  // Here we find assets that have been removed from the Assets.json
  for (const versionAsset of versions[config.newTag].contracts.Assets) {
    if (!jsonAssets.find((ja) => ja.assetAddress === versionAsset.assetAddress)) {
      assetsRemovedFromJson.push(versionAsset);
    }
  }

  console.log("Found removed assets", assetsRemovedFromJson);
  // Here we check if they're still enabled in the AssetHandler (via the poolFactory);
  for (const removedAsset of assetsRemovedFromJson) {
    const isEnabled = await poolFactory.isValidAsset(removedAsset.assetAddress);

    if (isEnabled) {
      assetAddressesToRemove.push(removedAsset.assetAddress);
    }
  }

  if (assetAddressesToRemove.length) {
    const deployedFunds = await poolFactory.getDeployedFunds();

    // This will be slow
    // Here we check that no pools have a balance of the asset we're removing
    // Comment this out if you want to by pass it
    for (const asset of assetAddressesToRemove) {
      console.log("Checking if any pool has a balance of", asset);
      const results = await executeInSeries(
        deployedFunds.map((fund) => async () => {
          console.log("Checking: ", fund);
          const pool = await ethers.getContractAt("PoolLogic", fund);
          const managerLogic = await ethers.getContractAt("PoolManagerLogic", await pool.poolManagerLogic());
          const isSupported = await managerLogic["isSupportedAsset(address)"](asset);
          if (isSupported) {
            console.log("Found fund with asset", fund);
            return fund;
          }
        }),
      );
      const filteredResults = results.filter(Boolean);
      if (filteredResults.length) {
        console.log("Pools that contain: ", asset, filteredResults);
        throw new Error("Cannot remove asset because pools contain it");
      }

      console.log("Checking finished of", asset);
    }

    console.log("AssetsJob: Removing Assets", assetAddressesToRemove);

    if (config.execute) {
      const AssetHandlerLogic = await hre.artifacts.readArtifact("AssetHandler");
      const assetHandlerLogic = new ethers.utils.Interface(AssetHandlerLogic.abi);
      for (const asset of assetAddressesToRemove) {
        console.log("Proposing tx to remove", asset);
        const removeAssetABI = assetHandlerLogic.encodeFunctionData("removeAsset", [asset]);
        await proposeTx(
          versions[config.oldTag].contracts.AssetHandlerProxy,
          removeAssetABI,
          "Remove asset from Asset Handler",
          config,
          addresses,
        );
      }

      const removedAssets = new Set<string>(assetAddressesToRemove);
      // Filter out any assets that have been removed
      const withoutRemoved = (versions[config.newTag].contracts.Assets || []).filter(
        (existingAsset) => !removedAssets.has(existingAsset.assetAddress),
      );
      versions[config.newTag].contracts.Assets = withoutRemoved;
      versions[config.newTag].contracts.RemovedAssets = (versions[config.newTag].contracts.RemovedAssets || []).concat(
        assetsRemovedFromJson,
      );
    }
  }
};
