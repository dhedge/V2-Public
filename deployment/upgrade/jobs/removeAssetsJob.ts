import fs from "fs";
import util from "util";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTransactions } from "../../deploymentHelpers";
import { aggregate3InChunks, getMulticall3 } from "../../multicall";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../types";
import { TDeployedAsset } from "./oracles/oracleTypes";
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
    const deployedFunds: string[] = await poolFactory.getDeployedFunds();
    const fundsWithAssetsToRemove: string[] = [];

    // Reads are batched through Multicall3 to avoid a per-fund fan-out that resets flaky RPCs.
    const multicall = getMulticall3(ethers.provider);
    const poolLogicInterface = new ethers.utils.Interface(["function poolManagerLogic() view returns (address)"]);
    const managerLogicInterface = new ethers.utils.Interface([
      "function isSupportedAsset(address) view returns (bool)",
      "function assetBalance(address) view returns (uint256)",
    ]);

    console.log(
      `Checking ${assetAddressesToRemove.length} asset(s) across ${deployedFunds.length} funds via multicall...`,
    );

    // Pass 1: resolve each fund's PoolManagerLogic.
    const managerLogicResults = await aggregate3InChunks(
      multicall,
      deployedFunds.map((fund) => ({
        target: fund,
        allowFailure: true,
        callData: poolLogicInterface.encodeFunctionData("poolManagerLogic"),
      })),
    );
    // Fails closed: a skipped fund would not be counted by the still-enabled safety gate below, so
    // the asset could be removed from the AssetHandler while that fund still supports it,
    // permanently breaking its pricing.
    const funds = deployedFunds.map((fund, i) => {
      const result = managerLogicResults[i];
      if (!result.success || result.returnData === "0x") {
        throw new Error(`Scan incomplete: poolManagerLogic() failed for fund ${fund}; aborting`);
      }
      const managerLogic: string = poolLogicInterface.decodeFunctionResult("poolManagerLogic", result.returnData)[0];
      return { fund, managerLogic };
    });
    console.log(`Pass 1: resolved ${funds.length}/${deployedFunds.length} funds (poolManagerLogic)`);

    // Pass 2: isSupportedAsset(asset) for every (asset, fund) pair. Call order is
    // asset-major: index === assetIndex * funds.length + fundIndex.
    const supportResults = await aggregate3InChunks(
      multicall,
      assetAddressesToRemove.flatMap((asset) =>
        funds.map(({ managerLogic }) => ({
          target: managerLogic,
          allowFailure: true,
          callData: managerLogicInterface.encodeFunctionData("isSupportedAsset", [asset]),
        })),
      ),
    );

    const supportedPairs: { asset: string; fund: string; managerLogic: string }[] = [];
    assetAddressesToRemove.forEach((asset, assetIndex) => {
      funds.forEach(({ fund, managerLogic }, fundIndex) => {
        const result = supportResults[assetIndex * funds.length + fundIndex];
        if (!result.success || result.returnData === "0x") {
          throw new Error(`Scan incomplete: isSupportedAsset(${asset}) failed for fund ${fund}; aborting`);
        }
        if (managerLogicInterface.decodeFunctionResult("isSupportedAsset", result.returnData)[0]) {
          supportedPairs.push({ asset, fund, managerLogic });
        }
      });
    });
    console.log(
      `Pass 2: ${supportResults.length} support checks (= ${assetAddressesToRemove.length} assets × ${funds.length} funds), ${supportedPairs.length} supported`,
    );

    // Pass 3: PoolManagerLogic.assetBalance(asset) only for supported pairs.
    const balanceResults = await aggregate3InChunks(
      multicall,
      supportedPairs.map(({ asset, managerLogic }) => ({
        target: managerLogic,
        allowFailure: true,
        callData: managerLogicInterface.encodeFunctionData("assetBalance", [asset]),
      })),
    );
    console.log(`Pass 3: ${balanceResults.length} balance checks (= ${supportedPairs.length} supported pairs)`);

    // Per-asset reporting + gather every fund that still has the asset enabled.
    // Here we check that no pools have enabled the asset we're removing
    // Comment this loop out if you want to by pass it
    for (const asset of assetAddressesToRemove) {
      const supportingFunds: string[] = [];
      const fundsWithPositiveBalance: string[] = [];

      supportedPairs.forEach((pair, i) => {
        if (pair.asset !== asset) return;
        supportingFunds.push(pair.fund);
        const balanceResult = balanceResults[i];
        if (balanceResult.success && balanceResult.returnData !== "0x") {
          const balance = managerLogicInterface.decodeFunctionResult("assetBalance", balanceResult.returnData)[0];
          if (balance.gt(0)) fundsWithPositiveBalance.push(pair.fund);
        }
      });

      if (supportingFunds.length) {
        console.log("Pools that contain: ", asset, util.inspect(supportingFunds, { maxArrayLength: null }));
        fundsWithAssetsToRemove.push(...supportingFunds);
      }
      console.log(
        "Pools with positive balance of: ",
        asset,
        util.inspect(fundsWithPositiveBalance, { maxArrayLength: null }),
      );
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
