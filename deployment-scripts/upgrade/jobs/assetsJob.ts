import csv from "csvtojson";
import fs from "fs";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { AssetHandlerInterface } from "../../../types/AssetHandler";
import { hasDuplicates, proposeTx } from "../../Helpers";
import { ICSVAsset, IJob, IProposeTxProperties, IUpgradeConfig, IVersions } from "../../types";
import {
  getOracle,
  IBalancerAsset,
  deployBalancerV2LpAggregator,
  deployBalancerLpStablePoolAggregator,
} from "./assetsJobHelpers";

// Todo: Combine csvAssets and Balancer Assets into one JSON file (move away from csv)
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
  let newOracles: ICSVAsset[] = [];

  // look up to check if csvAsset is in the current versions
  const fileName = filenames.assetsFileName;
  if (!fileName) {
    throw new Error("No assetFileName configured");
  }

  const csvAssets: ICSVAsset[] = await csv().fromFile(fileName);

  // Check for any accidental duplicate addresses or price feeds in the CSV
  if (await hasDuplicates(csvAssets, "assetAddress")) throw "Duplicate 'Address' field found in assets CSV";
  if (await hasDuplicates(csvAssets, "oracleAddress")) throw "Duplicate 'oracleAddress' field found in assets CSV";

  for (const csvAsset of [...csvAssets]) {
    // TODO: We don't redeploy any assets that are already configure in Versions.json if the configuration changes
    // For now, to redeploy an asset, delete it manually from versions.json.
    const foundInVersions = versions[config.newTag].contracts.Assets?.some(
      (x) => x.assetAddress.toLowerCase() == csvAsset.assetAddress.toLowerCase(),
    );

    if (!foundInVersions) {
      console.log("Will Deploy Asset:", csvAsset);
      if (config.execute) {
        const oracle = await getOracle(hre, csvAsset, versions);
        newOracles.push(oracle);
      }
    }
  }

  // Should refactor not to use require and add types for what a balancerLp is
  const balancerLps: IBalancerAsset[] = filenames.balancerConfigFileName
    ? JSON.parse(fs.readFileSync(filenames.balancerConfigFileName, "utf-8"))
    : [];
  const poolFactoryProxy = versions[config.oldTag].contracts.PoolFactoryProxy;

  for (const balancerLp of balancerLps) {
    if (!addresses.balancerV2VaultAddress) {
      throw new Error("No balancerV2VaultAddress configured");
    }

    const foundInVersions = versions[config.newTag].contracts.Assets?.some(
      (x) => balancerLp.address.toLowerCase() == x.assetAddress.toLowerCase(),
    );

    if (!foundInVersions) {
      console.log("Will deploy Balancer V2 LP asset", balancerLp.name);
      if (config.execute) {
        // Weighted pool
        if (balancerLp.oracleName === "BalancerV2LPAggregator") {
          // Deploy Balancer LP Aggregator
          console.log("Deploying ", balancerLp.name);
          const balancerV2Aggregator = await deployBalancerV2LpAggregator(
            addresses.balancerV2VaultAddress,
            poolFactoryProxy,
            balancerLp.data,
            hre,
          );
          console.log(`${balancerLp.name} BalancerV2LPAggregator deployed at ${balancerV2Aggregator}`);
          newOracles.push({
            assetName: balancerLp.name,
            assetAddress: balancerLp.data.pool,
            assetType: balancerLp.assetType,
            oracleAddress: balancerV2Aggregator,
            oracleName: "BalancerV2LPAggregator",
          });
        }

        // Stable pool
        if (balancerLp.oracleName === "BalancerLpStablePoolAggregator") {
          // Deploy Balancer LP Stable Pool Aggregator
          console.log("Deploying ", balancerLp.name);
          const balancerLpStablePoolAggregator = await deployBalancerLpStablePoolAggregator(
            hre,
            poolFactoryProxy,
            balancerLp.data.pool,
          );
          console.log(
            `${balancerLp.name} deployBalancerStablePoolAggregator deployed at ${balancerLpStablePoolAggregator}`,
          );
          newOracles.push({
            assetName: balancerLp.name,
            assetAddress: balancerLp.data.pool,
            assetType: balancerLp.assetType,
            oracleAddress: balancerLpStablePoolAggregator,
            oracleName: "BalancerLpStablePoolAggregator",
          });
        }
      }
    }
  }

  console.log("AssetsJob: Proposing New Assets");
  const AssetHandlerLogic = await hre.artifacts.readArtifact("AssetHandler");
  const assetHandlerLogic = new ethers.utils.Interface(AssetHandlerLogic.abi);
  // We need to convert them into the
  const assetHanderAssets: { asset: string; assetType: number; aggregator: string }[] = newOracles.map((x) => {
    return {
      asset: x.assetAddress,
      assetType: x.assetType,
      aggregator: x.oracleAddress,
    };
  });

  const addAssetsABI = assetHandlerLogic.encodeFunctionData("addAssets", [assetHanderAssets]);

  if (newOracles.length > 0) {
    await proposeTx(
      versions[config.oldTag].contracts.AssetHandlerProxy,
      addAssetsABI,
      "Update assets in Asset Handler",
      config,
      addresses,
    );
    versions[config.newTag].contracts.Assets = [...(versions[config.newTag].contracts.Assets || []), ...newOracles];
  }
};
