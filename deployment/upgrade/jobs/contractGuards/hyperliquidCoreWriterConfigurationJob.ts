import fs from "fs";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { MetaTransactionData, proposeTransactions } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";

// HIP-3 asset IDs start at 100_000. DexId = (assetId - 100_000) / 10_000.
const HIP3_ASSET_ID_THRESHOLD = 100_000;

function getHip3DexId(assetId: number): number {
  return Math.floor((assetId - HIP3_ASSET_ID_THRESHOLD) / 10_000);
}

export const hyperliquidCoreWriterConfigurationJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  console.log("Will update HyperliquidCoreWriterContractGuard configuration");

  const approvedPerpsPath = filenames.approvedPerpsFileName;
  if (!approvedPerpsPath) {
    console.log("No approvedPerpsFileName configured, skipping");
    return;
  }

  const coreWriterGuardProxy = versions[config.newTag].contracts.HyperliquidCoreWriterContractGuardProxy;
  if (!coreWriterGuardProxy) {
    console.log("HyperliquidCoreWriterContractGuardProxy not found in versions, skipping");
    return;
  }

  const newPerps: { perpName: string; assetId: number; approved: boolean }[] = JSON.parse(
    fs.readFileSync(approvedPerpsPath, "utf-8"),
  );

  const existingPerps = versions[config.newTag].config.hyperliquidCoreWriterGuard?.approvedPerps ?? [];

  const addedPerps = newPerps.filter(
    (newPerp) => !existingPerps.some((existing) => existing.assetId === newPerp.assetId && existing.approved),
  );

  const removedPerps = existingPerps.filter(
    (existing) => existing.approved && !newPerps.some((newPerp) => newPerp.assetId === existing.assetId),
  );

  console.log("New approved perps: ", addedPerps);
  console.log("Removed perps: ", removedPerps);

  if (addedPerps.length === 0 && removedPerps.length === 0) {
    console.log("No perp approval changes, skipping");
    return;
  }

  const HyperliquidCoreWriterContractGuard = await hre.artifacts.readArtifact("HyperliquidCoreWriterContractGuard");
  const guardInterface = new hre.ethers.utils.Interface(HyperliquidCoreWriterContractGuard.abi);
  const guardContract = new hre.ethers.Contract(coreWriterGuardProxy, guardInterface, hre.ethers.provider);

  // For any added HIP-3 perps, ensure their dex IDs are enabled first.
  const hip3DexIdsNeeded = [
    ...new Set(addedPerps.filter((p) => p.assetId >= HIP3_ASSET_ID_THRESHOLD).map((p) => getHip3DexId(p.assetId))),
  ];

  const dexIdsToEnable: number[] = [];
  for (const dexId of hip3DexIdsNeeded) {
    const isEnabled: boolean = await guardContract.isEnabledDexId(dexId);
    if (!isEnabled) {
      dexIdsToEnable.push(dexId);
    }
  }

  const transactions: MetaTransactionData[] = [];

  if (dexIdsToEnable.length > 0) {
    console.log("HIP-3 dex IDs to enable: ", dexIdsToEnable);
    transactions.push({
      to: coreWriterGuardProxy,
      data: guardInterface.encodeFunctionData("setDexIdStatus", [
        dexIdsToEnable.map((dexId) => ({ dexId, status: 1 /* DexStatus.ENABLED */ })),
      ]),
      value: "0",
    });
  }

  const approvalSettings = [
    ...addedPerps.map(({ assetId }) => ({ assetId, approved: true })),
    ...removedPerps.map(({ assetId }) => ({ assetId, approved: false })),
  ];

  transactions.push({
    to: coreWriterGuardProxy,
    data: guardInterface.encodeFunctionData("setApprovedAssets", [approvalSettings]),
    value: "0",
  });

  if (config.execute) {
    await proposeTransactions(
      transactions,
      "HyperliquidCoreWriterContractGuard - Update approved perp assets",
      config,
      addresses,
    );
  }

  versions[config.newTag].config.hyperliquidCoreWriterGuard = { approvedPerps: newPerps };
};
