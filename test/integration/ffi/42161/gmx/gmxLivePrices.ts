// Fetch and cache the real signed reports consumed by GMX keeper executions.
import fs from "node:fs";
import path from "node:path";

import dotenv from "dotenv";
import { ethers } from "ethers";

dotenv.config({ quiet: true });

const PRICE_API_URL = "https://arbitrum-api.gmxinfra.io/signed_prices/latest";
const LIVE_CACHE_TTL_MS = 30 * 1_000;
const LOCK_STALE_MS = 60 * 1_000;
const FORK_LEAD_SECONDS = 30;
const REPORT_COUNT = 3;
const REPORT_POLL_MS = 250;
const REPORT_TIMEOUT_MS = 15_000;

type SignedPrice = {
  tokenAddress: string;
  blob: string;
  minBlockTimestamp: number;
  maxBlockTimestamp: number;
  minPriceFull: string;
  maxPriceFull: string;
};

type PriceApiResponse = {
  signedPrices: SignedPrice[];
};

type PriceCache = {
  fetchedAt: number;
  forkBlockNumber: string;
  forkBlockTimestamp: number;
  reports: PriceApiResponse[];
};

type RpcBlock = {
  number: bigint;
  timestamp: number;
};

const sleep = (milliseconds: number): Promise<void> => new Promise((resolve) => setTimeout(resolve, milliseconds));

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function parsePriceResponse(value: unknown): PriceApiResponse {
  if (!isRecord(value) || !Array.isArray(value.signedPrices)) {
    throw new Error("GMX price API returned an invalid response");
  }

  const signedPrices = value.signedPrices.map((item): SignedPrice => {
    if (
      !isRecord(item) ||
      typeof item.tokenAddress !== "string" ||
      typeof item.blob !== "string" ||
      typeof item.minBlockTimestamp !== "number" ||
      typeof item.maxBlockTimestamp !== "number" ||
      typeof item.minPriceFull !== "string" ||
      typeof item.maxPriceFull !== "string"
    ) {
      throw new Error("GMX price API returned a malformed signed price");
    }

    return {
      tokenAddress: ethers.utils.getAddress(item.tokenAddress),
      blob: item.blob,
      minBlockTimestamp: item.minBlockTimestamp,
      maxBlockTimestamp: item.maxBlockTimestamp,
      minPriceFull: item.minPriceFull,
      maxPriceFull: item.maxPriceFull,
    };
  });

  return { signedPrices };
}

function readCache(cacheFile: string, maxAgeMs?: number): PriceCache | undefined {
  try {
    const parsed = JSON.parse(fs.readFileSync(cacheFile, "utf8")) as unknown;
    if (
      !isRecord(parsed) ||
      typeof parsed.fetchedAt !== "number" ||
      typeof parsed.forkBlockNumber !== "string" ||
      typeof parsed.forkBlockTimestamp !== "number" ||
      !Array.isArray(parsed.reports) ||
      parsed.reports.length < REPORT_COUNT
    ) {
      return undefined;
    }

    if (maxAgeMs !== undefined && Date.now() - parsed.fetchedAt > maxAgeMs) {
      return undefined;
    }

    const reports = parsed.reports.map((report) => parsePriceResponse(report));
    const earliestReportTimestamp = Math.min(...reports[0].signedPrices.map((price) => price.minBlockTimestamp));
    if (parsed.forkBlockTimestamp > earliestReportTimestamp - FORK_LEAD_SECONDS) {
      return undefined;
    }

    return {
      fetchedAt: parsed.fetchedAt,
      forkBlockNumber: parsed.forkBlockNumber,
      forkBlockTimestamp: parsed.forkBlockTimestamp,
      reports,
    };
  } catch {
    return undefined;
  }
}

async function fetchJson(url: string, init?: RequestInit): Promise<unknown> {
  const response = await fetch(url, {
    ...init,
    signal: AbortSignal.timeout(10_000),
  });
  if (!response.ok) {
    throw new Error(`Request to ${new URL(url).host} failed with HTTP ${response.status}`);
  }
  return response.json() as Promise<unknown>;
}

async function fetchBlock(rpcUrl: string, block: "latest" | bigint): Promise<RpcBlock> {
  const blockTag = block === "latest" ? block : `0x${block.toString(16)}`;
  const blockResponse = await fetchJson(rpcUrl, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      jsonrpc: "2.0",
      method: "eth_getBlockByNumber",
      params: [blockTag, false],
      id: 1,
    }),
  });

  if (!isRecord(blockResponse) || !isRecord(blockResponse.result)) {
    throw new Error("Arbitrum RPC returned an invalid latest block");
  }

  const numberHex = blockResponse.result.number;
  const timestampHex = blockResponse.result.timestamp;
  if (typeof numberHex !== "string" || typeof timestampHex !== "string") {
    throw new Error("Arbitrum latest block is missing its number or timestamp");
  }

  return {
    number: BigInt(numberHex),
    timestamp: Number(BigInt(timestampHex)),
  };
}

async function findForkBlock(rpcUrl: string, reportTimestamp: number): Promise<RpcBlock> {
  const latest = await fetchBlock(rpcUrl, "latest");
  if (latest.timestamp <= reportTimestamp) return latest;

  let upper = latest;
  let searchWindow = 4_096n;
  let lower = await fetchBlock(rpcUrl, latest.number > searchWindow ? latest.number - searchWindow : 0n);

  while (lower.timestamp > reportTimestamp && lower.number > 0n) {
    upper = lower;
    searchWindow *= 2n;
    lower = await fetchBlock(rpcUrl, lower.number > searchWindow ? lower.number - searchWindow : 0n);
  }

  while (upper.number - lower.number > 1n) {
    const middle = await fetchBlock(rpcUrl, lower.number + (upper.number - lower.number) / 2n);
    if (middle.timestamp <= reportTimestamp) {
      lower = middle;
    } else {
      upper = middle;
    }
  }

  if (lower.timestamp > reportTimestamp) {
    throw new Error(`Could not find an Arbitrum block at or before GMX timestamp ${reportTimestamp}`);
  }
  return lower;
}

async function fetchFreshPrices(rpcUrl: string): Promise<PriceCache> {
  const reports: PriceApiResponse[] = [];
  const deadline = Date.now() + REPORT_TIMEOUT_MS;
  let previousTimestamp = 0;

  while (reports.length < REPORT_COUNT) {
    const prices = parsePriceResponse(await fetchJson(PRICE_API_URL));
    const reportTimestamp = Math.min(...prices.signedPrices.map((price) => price.minBlockTimestamp));
    if (reportTimestamp > previousTimestamp) {
      reports.push(prices);
      previousTimestamp = reportTimestamp;
    }
    if (reports.length < REPORT_COUNT) {
      if (Date.now() >= deadline) throw new Error("Timed out collecting consecutive GMX signed-price reports");
      await sleep(REPORT_POLL_MS);
    }
  }

  const reportTimestamp = Math.min(...reports[0].signedPrices.map((price) => price.minBlockTimestamp));
  if (reportTimestamp <= FORK_LEAD_SECONDS) throw new Error("GMX report timestamp is invalid");
  // Requests must predate their oracle report. Keep the fork state slightly farther
  // back because Pyth publish times can be a few seconds ahead of an Arbitrum block.
  const forkBlock = await findForkBlock(rpcUrl, reportTimestamp - FORK_LEAD_SECONDS);

  return {
    fetchedAt: Date.now(),
    forkBlockNumber: forkBlock.number.toString(),
    forkBlockTimestamp: forkBlock.timestamp,
    reports,
  };
}

function releaseStaleLock(lockDirectory: string): void {
  try {
    const age = Date.now() - fs.statSync(lockDirectory).mtimeMs;
    if (age > LOCK_STALE_MS) {
      fs.rmdirSync(lockDirectory);
    }
  } catch {
    // The lock disappeared between the existence and stat checks.
  }
}

async function loadLivePrices(cacheDirectory: string, rpcUrl: string): Promise<PriceCache> {
  const cacheFile = path.join(cacheDirectory, ".live-arbitrum.json");
  const lockDirectory = path.join(cacheDirectory, ".live-arbitrum.lock");
  fs.mkdirSync(cacheDirectory, { recursive: true });

  const cached = readCache(cacheFile, LIVE_CACHE_TTL_MS);
  if (cached) return cached;

  let ownsLock = false;
  while (!ownsLock) {
    try {
      fs.mkdirSync(lockDirectory);
      ownsLock = true;
    } catch (error) {
      if (!isRecord(error) || error.code !== "EEXIST") throw error;
      const sharedLivePrices = readCache(cacheFile, LIVE_CACHE_TTL_MS);
      if (sharedLivePrices) return sharedLivePrices;
      releaseStaleLock(lockDirectory);
      await sleep(100);
    }
  }

  try {
    const sharedLivePrices = readCache(cacheFile, LIVE_CACHE_TTL_MS);
    if (sharedLivePrices) return sharedLivePrices;

    const fresh = await fetchFreshPrices(rpcUrl);
    const temporaryFile = path.join(cacheDirectory, `.live-arbitrum.${process.pid}.${Date.now()}.tmp`);
    fs.writeFileSync(temporaryFile, `${JSON.stringify(fresh)}\n`, { flag: "wx" });
    fs.renameSync(temporaryFile, cacheFile);
    return fresh;
  } finally {
    fs.rmdirSync(lockDirectory);
  }
}

async function loadPrices(cacheDirectory: string, useCachedData: boolean, rpcUrl: string): Promise<PriceCache> {
  fs.mkdirSync(cacheDirectory, { recursive: true });
  if (!useCachedData) return loadLivePrices(cacheDirectory, rpcUrl);

  const fixture = readCache(path.join(cacheDirectory, "arbitrum.json"));
  if (!fixture) {
    throw new Error("The cached GMX fixture is missing or invalid; set USE_CACHED_GMX_DATA to false to use live data");
  }
  return fixture;
}

function encodeResult(cache: PriceCache, requestedTokens: string[]): string {
  const selectedReports = cache.reports.map((report) => {
    const byToken = new Map(report.signedPrices.map((price) => [price.tokenAddress.toLowerCase(), price]));
    return requestedTokens.map((token) => {
      const checksumToken = ethers.utils.getAddress(token);
      const price = byToken.get(checksumToken.toLowerCase());
      if (!price) throw new Error(`No GMX signed price found for ${checksumToken}`);
      return price;
    });
  });

  const reportTimestamps = selectedReports.map((selected) =>
    Math.min(...selected.map((price) => price.minBlockTimestamp)),
  );
  if (reportTimestamps[0] <= cache.forkBlockTimestamp) {
    throw new Error("Cached GMX prices predate the cached Arbitrum block");
  }
  for (let index = 1; index < reportTimestamps.length; index += 1) {
    if (reportTimestamps[index] <= reportTimestamps[index - 1]) {
      throw new Error("Cached GMX reports are not strictly increasing");
    }
  }

  return ethers.utils.defaultAbiCoder.encode(
    ["uint256", "uint256[]", "address[]", "bytes[][]", "uint256[][]", "uint256[][]"],
    [
      cache.forkBlockNumber,
      reportTimestamps,
      selectedReports[0].map((price) => price.tokenAddress),
      selectedReports.map((selected) => selected.map((price) => price.blob)),
      selectedReports.map((selected) => selected.map((price) => price.minPriceFull)),
      selectedReports.map((selected) => selected.map((price) => price.maxPriceFull)),
    ],
  );
}

async function main(): Promise<void> {
  const useCachedDataArgument = process.argv[2];
  if (useCachedDataArgument !== "true" && useCachedDataArgument !== "false") {
    throw new Error("The GMX cache-mode argument must be true or false");
  }

  const requestedTokens = process.argv.slice(3);
  if (requestedTokens.length === 0) throw new Error("At least one GMX token address is required");

  const rpcUrl = process.env.ARBITRUM_URL;
  if (!rpcUrl) throw new Error("ARBITRUM_URL must be configured");

  const cache = await loadPrices(path.resolve("swapdatas-cache/gmx"), useCachedDataArgument === "true", rpcUrl);
  process.stdout.write(encodeResult(cache, requestedTokens));
}

main().catch((error: unknown) => {
  const message = error instanceof Error ? (error.stack ?? error.message) : String(error);
  process.stderr.write(`${message}\n`);
  process.exitCode = 1;
});
