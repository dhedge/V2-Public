import { task, types } from "hardhat/config";
import { HYPERLIQUID_MAINNET_API_URL } from "./hyperliquidUtils";
import { hyperevmProdFileNames } from "./deploymentData";
import fs from "fs";

// Types for Hyperliquid API responses
interface PerpAssetInfo {
  name: string;
  szDecimals: number;
  maxLeverage: number;
  onlyIsolated: boolean;
}

interface PerpMetaResponse {
  universe: PerpAssetInfo[];
}

/**
 * Fetch perp metadata from Hyperliquid API.
 * For core perps (dex 0), uses the "meta" endpoint.
 * For HIP-3 perps (e.g., xyz), uses the "metaAndAssetCtxs" endpoint with dex name.
 */
async function fetchPerpMeta(apiUrl: string, dexName?: string): Promise<PerpMetaResponse> {
  const body = dexName ? { type: "metaAndAssetCtxs", dex: dexName } : { type: "meta" };

  const response = await fetch(apiUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    throw new Error(`Failed to fetch perp metadata: ${response.statusText}`);
  }

  // metaAndAssetCtxs returns [meta, assetCtxs], meta returns just the meta object
  if (dexName) {
    const [meta] = (await response.json()) as [PerpMetaResponse, unknown];
    return meta;
  }

  return response.json() as Promise<PerpMetaResponse>;
}

/**
 * Calculate asset ID based on dex type.
 * Core perps (dex 0): assetId = index
 * HIP-3 perps: assetId = 100000 + dexId * 10000 + index
 */
function calculateAssetId(index: number, dexId: number): number {
  if (dexId === 0) return index;
  return 100000 + dexId * 10000 + index;
}

/**
 * Find perp asset info by ticker name.
 * For HIP-3 perps, names are in format "dex:COIN" (e.g., "xyz:TSLA").
 * Accepts either the full name or just the coin part.
 */
function findPerpAssetByTicker(
  perpMeta: PerpMetaResponse,
  ticker: string,
): { asset: PerpAssetInfo; index: number } | null {
  const upperTicker = ticker.toUpperCase();
  const index = perpMeta.universe.findIndex((a) => {
    const name = a.name.toUpperCase();
    // Match full name (e.g., "xyz:TSLA") or just the coin part after ":"
    return name === upperTicker || name.split(":").pop() === upperTicker;
  });

  if (index === -1) {
    return null;
  }

  return {
    asset: perpMeta.universe[index],
    index,
  };
}

/**
 * Parse the tickers input - can be comma-separated tickers or a range (startIndex,count)
 * Examples:
 * - "BTC,ETH,SOL" - individual tickers
 * - "0,10" - range: starting at index 0, get 10 assets (indices 0-9)
 */
function parseTickersInput(
  input: string,
  perpMeta: PerpMetaResponse,
): { assets: Array<{ asset: PerpAssetInfo; index: number }>; isRange: boolean } {
  const parts = input.split(",").map((s) => s.trim());

  // Check if input is a range (two numbers)
  if (parts.length === 2) {
    const startIndex = parseInt(parts[0], 10);
    const count = parseInt(parts[1], 10);

    if (!isNaN(startIndex) && !isNaN(count)) {
      // It's a range
      if (startIndex < 0 || startIndex >= perpMeta.universe.length) {
        throw new Error(`Invalid start index: ${startIndex}. Must be between 0 and ${perpMeta.universe.length - 1}`);
      }

      const endIndex = Math.min(startIndex + count, perpMeta.universe.length);
      const assets: Array<{ asset: PerpAssetInfo; index: number }> = [];

      for (let i = startIndex; i < endIndex; i++) {
        assets.push({
          asset: perpMeta.universe[i],
          index: i,
        });
      }

      return { assets, isRange: true };
    }
  }

  // Otherwise, treat as comma-separated tickers
  const assets: Array<{ asset: PerpAssetInfo; index: number }> = [];
  const notFound: string[] = [];

  for (const ticker of parts) {
    const result = findPerpAssetByTicker(perpMeta, ticker);
    if (result) {
      assets.push(result);
    } else {
      notFound.push(ticker);
    }
  }

  if (notFound.length > 0) {
    throw new Error(`Perp assets not found: ${notFound.join(", ")}`);
  }

  return { assets, isRange: false };
}

/**
 * Resolves Hyperliquid perp asset info and adds entries to the approved perps JSON file.
 * The actual on-chain approval is handled by hyperliquidCoreWriterConfigurationJob in the upgrade flow.
 */
task("whitelistPerpAssets", "Resolve Hyperliquid perp asset info and add it to the approved perps config")
  .addParam(
    "tickers",
    "Comma-separated tickers (e.g., BTC,ETH,SOL) or range as 'startIndex,count' (e.g., 0,10)",
    undefined,
    types.string,
  )
  .addOptionalParam("dex", "HIP-3 perp dex name (e.g., 'xyz'). Omit for core perps.", undefined, types.string)
  .addOptionalParam(
    "dexid",
    "HIP-3 perp dex numeric ID (e.g., 1 for xyz). Required when --dex is set.",
    undefined,
    types.int,
  )
  .setAction(async (taskArgs) => {
    const { tickers, dex, dexid } = taskArgs;

    const isHip3 = !!dex;
    const perpDexId: number = isHip3 ? dexid : 0;

    if (isHip3 && dexid === undefined) {
      console.error("❌ --dexid is required when --dex is set.");
      return;
    }

    console.log(
      `\n🚀 Whitelisting Hyperliquid Perp Assets${isHip3 ? ` (HIP-3 dex: ${dex}, dex ID: ${perpDexId})` : " (core perps)"}\n`,
    );

    // Step 1: Fetch perp metadata from Hyperliquid API
    console.log(
      `📡 Fetching perp metadata from Hyperliquid API (${HYPERLIQUID_MAINNET_API_URL})${isHip3 ? ` for dex "${dex}"` : ""}...`,
    );
    const perpMeta = await fetchPerpMeta(HYPERLIQUID_MAINNET_API_URL, dex);
    console.log(`   Found ${perpMeta.universe.length} perp assets in the universe.\n`);

    // Step 2: Parse tickers input
    console.log(`🔍 Parsing tickers input: "${tickers}"`);
    let parsedAssets: { assets: Array<{ asset: PerpAssetInfo; index: number }>; isRange: boolean };

    try {
      parsedAssets = parseTickersInput(tickers, perpMeta);
    } catch (error) {
      console.error(`❌ ${error}`);
      console.log("\nAvailable perp assets (first 100):");
      perpMeta.universe.slice(0, 100).forEach((asset, index) => {
        console.log(`  ${index}: ${asset.name} (maxLeverage: ${asset.maxLeverage}x)`);
      });
      return;
    }

    const { assets, isRange } = parsedAssets;

    if (assets.length === 0) {
      console.error("❌ No valid assets to whitelist.");
      return;
    }

    console.log(`\n✅ Found ${assets.length} perp asset(s)${isRange ? " (range mode)" : " (ticker mode)"}:`);
    assets.forEach(({ asset, index }) => {
      const assetId = calculateAssetId(index, perpDexId);
      console.log(`   - ${asset.name} (assetId: ${assetId}, maxLeverage: ${asset.maxLeverage}x)`);
    });

    // Step 3: Update the approved perps JSON file
    const approvedPerpsPath = hyperevmProdFileNames.approvedPerpsFileName as string;
    let approvedPerps: Array<{ perpName: string; assetId: number; approved: boolean }> = [];

    if (fs.existsSync(approvedPerpsPath)) {
      approvedPerps = JSON.parse(fs.readFileSync(approvedPerpsPath, "utf-8"));
    }

    for (const { asset, index } of assets) {
      const assetId = calculateAssetId(index, perpDexId);
      const existingIndex = approvedPerps.findIndex((p) => p.assetId === assetId);
      const entry = { perpName: asset.name, assetId, approved: true };

      if (existingIndex >= 0) {
        approvedPerps[existingIndex] = entry;
      } else {
        approvedPerps.push(entry);
      }
    }

    approvedPerps.sort((a, b) => a.assetId - b.assetId);
    fs.writeFileSync(approvedPerpsPath, JSON.stringify(approvedPerps, null, 2));
    console.log(`\n✅ Updated ${approvedPerpsPath} with ${assets.length} perp asset(s)`);
    console.log(
      `\n📌 Next step: run the standard upgrade flow to approve assets on-chain via hyperliquidCoreWriterConfigurationJob.\n`,
    );
  });

export default {};
