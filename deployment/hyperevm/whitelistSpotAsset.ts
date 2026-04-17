import { task, types } from "hardhat/config";
import { HYPERLIQUID_MAINNET_API_URL } from "./hyperliquidUtils";
import { hyperevmProdFileNames } from "./deploymentData";
import fs from "fs";

// Constants
const USDC_TOKEN_INDEX = 0;
const ASSET_TYPE_HYPERLIQUID_SPOT = 40;
const BASE_SYSTEM_ADDRESS = BigInt("0x2000000000000000000000000000000000000000");
const HYPE_SYSTEM_ADDRESS = "0x2222222222222222222222222222222222222222";
const MAINNET_HYPE_TOKEN_INDEX = 150;
const USDC_USD_PRICE_FEED = "0xA0Adc43ce7AfE3EE7d7eac3C994E178D0620223B"; // Chainlink USDC/USD price feed

// Types for Hyperliquid API responses
interface EvmContract {
  address: string;
  // eslint-disable-next-line @typescript-eslint/naming-convention
  evm_extra_wei_decimals: number;
}

interface TokenInfo {
  name: string;
  szDecimals: number;
  weiDecimals: number;
  index: number;
  tokenId: string;
  isCanonical: boolean;
  evmContract: EvmContract | null;
  fullName: string | null;
}

/**
 * Extract the EVM contract address from the evmContract field
 */
function getEvmContractAddress(evmContract: EvmContract | null): string | null {
  if (!evmContract) {
    return null;
  }
  return evmContract.address;
}

interface SpotPair {
  name: string;
  tokens: [number, number]; // [baseTokenIndex, quoteTokenIndex]
  index: number;
  isCanonical: boolean;
}

interface SpotMetaResponse {
  tokens: TokenInfo[];
  universe: SpotPair[];
}

/**
 * Calculate the system address for a given token index.
 * Mirrors the Solidity getSystemAddress function.
 */
function getSystemAddress(tokenIndex: number): string {
  if (tokenIndex === MAINNET_HYPE_TOKEN_INDEX) {
    return HYPE_SYSTEM_ADDRESS;
  }

  const systemAddress = BASE_SYSTEM_ADDRESS + BigInt(tokenIndex);
  return "0x" + systemAddress.toString(16).padStart(40, "0");
}

/**
 * Fetch spot metadata from Hyperliquid API
 */
async function fetchSpotMeta(apiUrl: string): Promise<SpotMetaResponse> {
  const response = await fetch(apiUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ type: "spotMeta" }),
  });

  if (!response.ok) {
    throw new Error(`Failed to fetch spot metadata: ${response.statusText}`);
  }

  return response.json() as Promise<SpotMetaResponse>;
}

/**
 * Find spot asset info by ticker name
 */
function findSpotAssetByTicker(
  spotMeta: SpotMetaResponse,
  ticker: string,
): {
  token: TokenInfo;
  spotPair: SpotPair;
  spotIndex: number;
} | null {
  // Find the token by name (case insensitive)
  const token = spotMeta.tokens.find((t) => t.name.toUpperCase() === ticker.toUpperCase());

  if (!token) {
    return null;
  }

  // Find the spot pair where this token is the base and USDC (index 0) is the quote
  const spotPair = spotMeta.universe.find(
    (pair) => pair.tokens[0] === token.index && pair.tokens[1] === USDC_TOKEN_INDEX,
  );

  if (!spotPair) {
    return null;
  }

  return {
    token,
    spotPair,
    spotIndex: spotPair.index,
  };
}

/**
 * Deploys a HyperliquidSpotPriceAggregator for a spot asset and updates the assets JSON file.
 * The actual AssetHandler registration is handled by the standard assetsJob upgrade flow.
 */
task("whitelistSpotAsset", "Resolve Hyperliquid spot asset info and add it to the assets config for assetsJob")
  .addParam("ticker", "The ticker symbol of the spot asset (e.g., PURR, HYPE)", undefined, types.string)
  .setAction(async (taskArgs) => {
    const { ticker } = taskArgs;

    console.log(`\n🚀 Whitelisting Hyperliquid Spot Asset: ${ticker}\n`);

    // Step 1: Fetch spot metadata from Hyperliquid API
    console.log(`📡 Fetching spot metadata from Hyperliquid API (${HYPERLIQUID_MAINNET_API_URL})...`);
    const spotMeta = await fetchSpotMeta(HYPERLIQUID_MAINNET_API_URL);

    // Step 2: Find the spot asset by ticker
    console.log(`🔍 Looking for spot asset: ${ticker}`);
    const assetInfo = findSpotAssetByTicker(spotMeta, ticker);

    if (!assetInfo) {
      console.error(`❌ Error: Spot asset "${ticker}" not found or does not have a USDC quote pair.`);
      console.log("\nAvailable spot assets with USDC quote:");
      spotMeta.universe
        .filter((pair) => pair.tokens[1] === USDC_TOKEN_INDEX)
        .slice(0, 20)
        .forEach((pair) => {
          const baseToken = spotMeta.tokens.find((t) => t.index === pair.tokens[0]);
          console.log(
            `  - ${baseToken?.name || "Unknown"} (Token Index: ${pair.tokens[0]}, Spot Index: ${pair.index})`,
          );
        });
      return;
    }

    const { token, spotPair, spotIndex } = assetInfo;

    // Verify quote asset is USDC
    if (spotPair.tokens[1] !== USDC_TOKEN_INDEX) {
      const quoteToken = spotMeta.tokens.find((t) => t.index === spotPair.tokens[1]);
      console.error(
        `❌ Error: Quote asset for ${ticker} is not USDC. Quote token: ${quoteToken?.name || "Unknown"} (Index: ${spotPair.tokens[1]})`,
      );
      return;
    }

    // Extract the EVM contract address (the API returns an object, not a string)
    const evmContractAddress = getEvmContractAddress(token.evmContract);

    console.log(`\n✅ Found spot asset:`);
    console.log(`   Name: ${token.name}`);
    console.log(`   Token Index: ${token.index}`);
    console.log(`   Spot Index: ${spotIndex}`);
    console.log(`   Spot Pair Name: ${spotPair.name}`);
    console.log(`   EVM Contract: ${evmContractAddress || "None (will use system address)"}`);
    console.log(`   System Address: ${getSystemAddress(token.index)}`);

    // Step 3: Determine the asset address (EVM contract or system address)
    const assetAddress = evmContractAddress || getSystemAddress(token.index);
    console.log(`\n📋 Asset Address to use: ${assetAddress}`);

    const assetEntry = {
      assetName: token.name,
      assetAddress: assetAddress,
      assetType: ASSET_TYPE_HYPERLIQUID_SPOT.toString(),
      specificOracleConfig: {
        spotIndex: spotIndex,
        usdcUsdFeed: USDC_USD_PRICE_FEED,
      },
      oracleType: "HyperliquidSpotPriceAggregator",
    };

    // Summary
    console.log(`\n${"=".repeat(60)}`);
    console.log(`📊 Summary for ${ticker}`);
    console.log(`${"=".repeat(60)}`);
    console.log(`   Token Name: ${token.name}`);
    console.log(`   Token Index: ${token.index}`);
    console.log(`   Spot Index: ${spotIndex}`);
    console.log(`   Asset Address: ${assetAddress}`);
    console.log(`   Asset Type: ${ASSET_TYPE_HYPERLIQUID_SPOT} (Hyperliquid ERC20 Spot Linked Asset)`);
    console.log(`   USDC/USD Feed: ${USDC_USD_PRICE_FEED}`);
    console.log(`   EVM Contract Linked: ${evmContractAddress ? "Yes" : "No (using system address)"}`);
    console.log(`${"=".repeat(60)}\n`);

    // Update assets list JSON so assetsJob can pick it up during the upgrade flow
    const assetsListPath = hyperevmProdFileNames.assetsFileName;
    if (!assetsListPath) {
      throw new Error("No assetsFileName configured for hyperevm");
    }
    const assetsList = JSON.parse(fs.readFileSync(assetsListPath, "utf-8"));

    assetsList.push(assetEntry);

    fs.writeFileSync(assetsListPath, JSON.stringify(assetsList, null, 2));
    console.log(`✅ Updated ${assetsListPath} with new asset entry`);
    console.log(
      `\n📌 Next step: run the standard upgrade flow to deploy the aggregator and register the asset in AssetHandler via assetsJob.\n`,
    );
  });

export default {};
