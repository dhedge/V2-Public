import fs from "fs";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { deploy } from "../../deploy";
import { hasDuplicates, proposeTx } from "../../Helpers";
import { IJob, IProposeTxProperties, IUpgradeConfig, IVersions, TDeployedAsset } from "../../types";
import { getOracle } from "./oracles/assetsJobHelpers";
import { TAssetConfig } from "./oracles/oracleTypes";

// Todo: Combine jsonAssets and Balancer Assets into one JSON file (move away from csv)
export const assetsJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This optimally should not be mutated
  versions: IVersions,
  filenames: { assetsFileName?: string; balancerConfigFileName?: string },
  addresses: { balancerV2VaultAddress?: string } & IProposeTxProperties,
) => {
  console.log("Running Assets Job");
  const ethers = hre.ethers;
  const newAssets: TDeployedAsset[] = [];

  const filename = filenames.assetsFileName;
  if (!filename) {
    throw new Error("No assetFileName configured");
  }

  const jsonAssets: TAssetConfig[] = JSON.parse(fs.readFileSync(filename, "utf-8"));

  // Check for any accidental duplicate addresses or price feeds in the json file
  if (hasDuplicates(jsonAssets, (x) => x.assetAddress)) throw "Duplicate 'Address' field found in assets CSV";

  for (const jsonAsset of [...jsonAssets]) {
    const foundInVersions = versions[config.newTag].contracts.Assets?.some((deployedAsset) => {
      // We remove the deployed oracle address and then check all other fields are the same
      // JSON does need to be ordered for this to work, so might need to use node-hasher here
      if (deployedAsset.assetAddress == jsonAsset.assetAddress) {
        // eslint-disable-next-line @typescript-eslint/no-unused-vars
        const { oracleAddress, ...allOtherProps } = deployedAsset;
        return JSON.stringify(allOtherProps) === JSON.stringify(jsonAsset);
      } else {
        return false;
      }
    });

    if (!foundInVersions) {
      console.log("Will Deploy Asset:", jsonAsset);
      if (config.execute) {
        const oracle = await getOracle(hre, jsonAsset);
        newAssets.push(oracle);
      }
    }
  }

  const AssetHandlerLogic = await hre.artifacts.readArtifact("AssetHandler");
  const assetHandlerLogic = new ethers.utils.Interface(AssetHandlerLogic.abi);
  // We need to convert them into the
  const assetHanderAssets: { asset: string; assetType: number; aggregator: string }[] = newAssets.map((x) => {
    return {
      asset: x.assetAddress,
      assetType: x.assetType,
      aggregator: x.oracleAddress,
    };
  });

  const addAssetsABI = assetHandlerLogic.encodeFunctionData("addAssets", [assetHanderAssets]);

  if (newAssets.length > 0) {
    console.log("AssetsJob: Proposing New Assets");
    await proposeTx(
      versions[config.oldTag].contracts.AssetHandlerProxy,
      addAssetsABI,
      "Update assets in Asset Handler",
      config,
      addresses,
    );

    const assetsWithNewOracles = new Set<string>(newAssets.map((x) => x.assetAddress));
    // Filter out any assets that have a new oracle
    const existingAssets = (versions[config.newTag].contracts.Assets || []).filter(
      (existingAsset) => !assetsWithNewOracles.has(existingAsset.assetAddress),
    );
    console.log("New Assets", newAssets);
    versions[config.newTag].contracts.Assets = [...existingAssets, ...newAssets];
  }
};
