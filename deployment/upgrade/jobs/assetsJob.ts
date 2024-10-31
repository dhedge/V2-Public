import fs from "fs";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { hasDuplicates, proposeTx } from "../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions, TDeployedAsset } from "../../types";
import { configureContractGuard } from "./assetContractGuardHelpers";
import { getOracle } from "./oracles/assetsJobHelpers";
import { TAssetConfig } from "./oracles/oracleTypes";

export enum AssetType {
  "Chainlink direct USD price feed with 8 decimals" = 0,
  "Synthetix synth with Chainlink direct USD price feed" = 1,
  "Sushi LP tokens" = 2,
  "Aave V2 Lending Pool Asset" = 3,
  "Lending Enable Asset" = 4,
  "Quick LP tokens" = 5,
  "Balancer LP" = 6,
  "Uniswap V3 NFT Position Asset" = 7,
  "Aave V3 Lending Pool Asset" = 8,
  "Arrakis Liquidity Gauge V4 Asset" = 9,
  "Balancer V2 Gauge Asset" = 10,
  "Synthetix + LendingEnabled" = 14,
  "Velodrome LP/Gauge Asset" = 15,
  "Stargate Lp" = 16,
  "Mai Vault Asset" = 17,
  "Ramses LP/Gauge Asset" = 20,
  "Flat Money's UNIT" = 21,
  "Flat Money's Collateral" = 22,
  "Velodrome V2 LP/Gauge Asset" = 25,
  "Velodrome CL NFT Position Asset" = 26,
  "Flat Money's Leverage Asset" = 27,
  "Compound V3 Comet Asset" = 28,
  "Ramses CL NFT Position Asset" = 29,
  "EasySwapperV2 Unrolled Assets" = 30,
  "Lyra OptionMarketWrapper Asset" = 100,
  "Synthetix Futures Market Asset" = 101,
  "Synthetix PerpsV2 Market Asset" = 102,
  "Synthetix V3 Position Asset" = 103,
  "Synthetix V3 Perps Position Asset" = 104,
  "Reward Asset" = 200,
  "Deprecated Asset" = 999,
}

export const assetsJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
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
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  if (hasDuplicates(jsonAssets as any, (x: any) => x.assetAddress))
    throw "Duplicate 'Address' field found in assets CSV";

  for (const jsonAsset of [...jsonAssets]) {
    const foundInVersions = versions[config.newTag].contracts.Assets?.find((deployedAsset) => {
      return deployedAsset.assetAddress == jsonAsset.assetAddress;
    });

    let configChanged = false;
    let assetTypeChanged = false;
    let contractGuardConfigChanged = false;
    if (foundInVersions) {
      // We need to pluck oracleAddress out because that only exists in versions.json
      // eslint-disable-next-line @typescript-eslint/no-unused-vars
      const { oracleAddress, assetType, specificContractGuardConfig, ...allOtherProps } = foundInVersions;
      const {
        assetType: currentAssetType,
        specificContractGuardConfig: currentSpecificContractGuardConfig,
        ...assetConfig
      } = jsonAsset;
      // We remove the deployed oracle address and then check all other fields are the same
      configChanged = JSON.stringify(allOtherProps) !== JSON.stringify(assetConfig);
      contractGuardConfigChanged =
        JSON.stringify(specificContractGuardConfig) !== JSON.stringify(currentSpecificContractGuardConfig);
      assetTypeChanged = assetType != currentAssetType;
    }

    // If the config has changed then we need to redeploy the oracle
    if (configChanged || !foundInVersions) {
      console.log("Will Deploy Asset:", jsonAsset);
      if (config.execute) {
        const oracle = await getOracle(hre, jsonAsset);
        newAssets.push(oracle);
      }
    }
    // If only the assetType has changed there is no need to redeploy the oracle
    else if (assetTypeChanged) {
      console.log("Will Update assetType:", jsonAsset);
      if (config.execute) {
        newAssets.push({ ...foundInVersions, assetType: jsonAsset.assetType });
      }
    }

    // Some assets like ones with reward gauges require a contractGuard
    if (!foundInVersions || contractGuardConfigChanged) {
      const contractGuardName = jsonAsset.specificContractGuardConfig?.contractGuard;
      const extraContractGuardName = jsonAsset.specificContractGuardConfig?.extraContractGuard;
      if (!config.execute) {
        continue;
      }
      if (contractGuardName) {
        console.log("Will Deploy Contract Guard for:", jsonAsset);
        await configureContractGuard(config, hre, versions, filenames, addresses, jsonAsset, contractGuardName);
      }
      if (extraContractGuardName) {
        console.log("Will Deploy Extra Contract Guard for:", jsonAsset);
        await configureContractGuard(config, hre, versions, filenames, addresses, jsonAsset, extraContractGuardName);
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
