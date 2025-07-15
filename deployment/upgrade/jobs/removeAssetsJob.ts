import fs from "fs";
import util from "util";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTransactions } from "../../deploymentHelpers";
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
    if (!jsonAssets.find((ja) => ja.assetAddress.toLowerCase() === versionAsset.assetAddress.toLowerCase())) {
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
    const fundsWithAssetsToRemove: string[] = [];

    // Here we check that no pools have enabled the asset we're removing
    // Comment this loop out if you want to by pass it
    for (const asset of assetAddressesToRemove) {
      const fundsWithPositiveBalance: string[] = [];
      const assetContract = await ethers.getContractAt("contracts/interfaces/IERC20.sol:IERC20", asset);
      console.log("Checking if any pool has enabled: ", asset);
      const results = await Promise.all(
        deployedFunds.map(async (fund) => {
          const pool = await ethers.getContractAt("PoolLogic", fund);
          const managerLogic = await ethers.getContractAt("PoolManagerLogic", await pool.poolManagerLogic());
          const isSupported = await managerLogic["isSupportedAsset(address)"](asset);
          if (isSupported) {
            const balance = await assetContract.balanceOf(fund);
            if (balance.gt(0)) fundsWithPositiveBalance.push(fund);
            return fund;
          }
        }),
      );
      const filteredResults = results.filter((poolAddress): poolAddress is string => poolAddress !== undefined);
      if (filteredResults.length) {
        console.log("Pools that contain: ", asset, util.inspect(filteredResults, { maxArrayLength: null }));
        fundsWithAssetsToRemove.push(...filteredResults);
      }

      console.log(
        "Pools with positive balance of: ",
        asset,
        util.inspect(fundsWithPositiveBalance, { maxArrayLength: null }),
      );

      console.log("Checking finished of", asset);
    }

    console.log("Funds with assets to remove", util.inspect(fundsWithAssetsToRemove, { maxArrayLength: null }));

    console.log("AssetsJob: Removing Assets", assetAddressesToRemove);

    if (config.execute && fundsWithAssetsToRemove.length === 0) {
      const AssetHandlerLogic = await hre.artifacts.readArtifact("AssetHandler");
      const assetHandlerInterface = new ethers.utils.Interface(AssetHandlerLogic.abi);

      console.log("Proposing tx to remove", assetAddressesToRemove);
      await proposeTransactions(
        assetAddressesToRemove.map((asset) => ({
          to: versions[config.oldTag].contracts.AssetHandlerProxy,
          value: "0",
          data: assetHandlerInterface.encodeFunctionData("removeAsset", [asset]),
        })),
        "Remove assets from Asset Handler",
        config,
        addresses,
      );

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
