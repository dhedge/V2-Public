import fs from "fs";
import path from "path";
import { HardhatRuntimeEnvironment } from "hardhat/types";

/**
 * Verifies a deployed contract straight through the Etherscan V2 API, with no hardhat-verify
 * involved: the standard-JSON payload is rebuilt from this repo's own artifacts (build-info pruned
 * to the contract's import graph). An accepted submission may remain queued on the explorer, so
 * callers can continue deployment and check verification later.
 *
 * Assumes the unified V2 API (api.etherscan.io/v2/api?chainid=...) plus ETHERSCAN_API_KEY in .env.
 */
const API = "https://api.etherscan.io/v2/api";
const REQUEST_TIMEOUT_MS = 15000;
const OUTPUT_SELECTION = { "*": { "*": ["abi", "evm.bytecode", "evm.deployedBytecode", "metadata"] } };

/** Same three parameters `tryVerify` used to pass to the `verify:verify` task. */
type VerifyViaApiArgs = { address: string; contract: string; constructorArguments: unknown[] };

export type VerifyViaApiResult = { status: "verified" } | { status: "queued"; guid: string };

/** `deployedLinkReferences` of a hardhat artifact. */
type LinkReferences = Record<string, Record<string, { start: number; length: number }[]>>;

/** Build-info fields needed to rebuild the compiler input. */
type BuildInfo = {
  solcLongVersion: string;
  input: { settings: Record<string, unknown>; sources: Record<string, { content: string }> };
  output: { sources: Record<string, { ast: unknown }> };
};

/** Etherscan V2 response envelope. */
type ExplorerResponse = { status?: string; message?: string; result?: unknown };

/** Build-info files are tens of megabytes, so keep the parsed copy. */
const buildInfoCache = new Map<string, BuildInfo>();

const text = (value: unknown) => (typeof value === "string" ? value : undefined);
const sourceCodeOf = (value: unknown) =>
  Array.isArray(value) ? (value[0] as { SourceCode?: string } | undefined)?.SourceCode : undefined;
const alreadyVerified = (value: unknown) => text(value)?.toLowerCase().includes("already verified") ?? false;

/** Limit both the connection and response body read without logging the API-key-bearing URL. */
const readResponse = async (
  url: string,
  request?: { method: string; headers: Record<string, string>; body: string },
): Promise<ExplorerResponse> => {
  const controller = new AbortController();
  let timedOut = false;
  const timeout = setTimeout(() => {
    timedOut = true;
    controller.abort();
  }, REQUEST_TIMEOUT_MS);

  try {
    const response = await fetch(url, { ...request, signal: controller.signal });
    if (!response.ok) throw new Error(`Explorer responded with HTTP ${response.status}`);
    const body: unknown = await response.json();
    if (typeof body !== "object" || body === null || Array.isArray(body)) {
      throw new Error("Explorer returned an invalid response");
    }
    return body as ExplorerResponse;
  } catch (error) {
    if (timedOut) throw new Error(`Explorer request timed out after ${REQUEST_TIMEOUT_MS} ms`);
    throw error;
  } finally {
    clearTimeout(timeout);
  }
};

/** GET: chainid, the API key and the action all travel in the query string. */
const explorerGet = async (chainId: number, apiKey: string, params: Record<string, string>) => {
  const query = new URLSearchParams({ chainid: String(chainId), apikey: apiKey, module: "contract", ...params });
  return readResponse(`${API}?${query}`);
};

/** POST: chainid in the URL, the form fields in the body, as Etherscan V2 expects. */
const explorerPost = async (chainId: number, apiKey: string, params: Record<string, string>) => {
  const body = new URLSearchParams({ apikey: apiKey, module: "contract", ...params }).toString();
  const request = { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body };
  return readResponse(`${API}?chainid=${chainId}`, request);
};

/** Linked library addresses, read from the deployed code at the artifact's link slots. */
const linkedLibraries = async (hre: HardhatRuntimeEnvironment, references: LinkReferences, address: string) => {
  const libraries: Record<string, Record<string, string>> = {};
  if (Object.keys(references).length === 0) return libraries;

  const code = await hre.ethers.provider.getCode(address);
  for (const [file, libs] of Object.entries(references)) {
    libraries[file] = {};
    for (const [name, slots] of Object.entries(libs)) {
      const { start, length } = slots[0];
      libraries[file][name] = `0x${code.slice(2 + start * 2, 2 + (start + length) * 2)}`;
    }
  }
  return libraries;
};

/** Standard-JSON payload: the build-info's sources pruned to the contract's import graph. */
const compilerInput = (
  hre: HardhatRuntimeEnvironment,
  contract: string,
  libraries: Record<string, Record<string, string>>,
) => {
  const [sourceName, contractName] = contract.split(":");
  const artifactDir = path.join(hre.config.paths.artifacts, sourceName);
  const debug = JSON.parse(fs.readFileSync(path.join(artifactDir, `${contractName}.dbg.json`), "utf8"));
  const buildInfoPath = path.resolve(artifactDir, debug.buildInfo);

  const cached = buildInfoCache.get(buildInfoPath);
  const info = cached ?? (JSON.parse(fs.readFileSync(buildInfoPath, "utf8")) as BuildInfo);
  if (cached === undefined) buildInfoCache.set(buildInfoPath, info);

  const importsOf = (name: string): string[] => {
    const found: string[] = [];
    const walk = (node: unknown): void => {
      if (Array.isArray(node)) return node.forEach(walk);
      if (typeof node !== "object" || node === null) return;
      const entry = node as Record<string, unknown>;
      if (entry.nodeType === "ImportDirective") found.push(String(entry.absolutePath));
      Object.values(entry).forEach(walk);
    };
    walk(info.output.sources[name].ast);
    return found;
  };

  // Set iteration also visits entries added while iterating, so this is the whole import closure.
  const reachable = new Set([sourceName]);
  for (const name of reachable) {
    for (const imported of importsOf(name)) reachable.add(imported);
  }

  const sources = Object.fromEntries(
    [...reachable].map((name) => [name, { content: info.input.sources[name].content }]),
  );
  const settings = { ...info.input.settings, outputSelection: OUTPUT_SELECTION, libraries };

  return {
    json: JSON.stringify({ language: "Solidity", sources, settings }),
    compilerVersion: `v${info.solcLongVersion}`,
  };
};

/** Submits `address` for verification; a queued submission does not block deployment. */
export const verifyViaApi = async (
  hre: HardhatRuntimeEnvironment,
  { address, contract, constructorArguments }: VerifyViaApiArgs,
): Promise<VerifyViaApiResult> => {
  const apiKey = process.env.ETHERSCAN_API_KEY;
  if (!apiKey?.trim()) throw new Error("ETHERSCAN_API_KEY is not set");

  const chainId = hre.network.config.chainId;
  if (chainId === undefined) throw new Error(`Network ${hre.network.name} has no chainId`);

  const sourceLookup = () => explorerGet(chainId, apiKey, { action: "getsourcecode", address });
  const lookup = await sourceLookup();
  const lookupMessage = text(lookup.result);
  const noRecords = lookup.status === "0" && /^(no records found|no data found)$/i.test(lookupMessage ?? "");
  if (!noRecords && (lookup.status !== "1" || !Array.isArray(lookup.result))) {
    throw new Error(
      `Explorer could not check verification of ${address}: ${lookupMessage ?? lookup.message ?? "unknown error"}`,
    );
  }
  if (sourceCodeOf(lookup.result)) {
    console.log(`The contract ${address} has already been verified on the block explorer.`);
    return { status: "verified" };
  }

  const [sourceName, contractName] = contract.split(":");
  const artifact = JSON.parse(
    fs.readFileSync(path.join(hre.config.paths.artifacts, sourceName, `${contractName}.json`), "utf8"),
  );
  const libraries = await linkedLibraries(hre, artifact.deployedLinkReferences ?? {}, address);
  const input = compilerInput(hre, contract, libraries);
  const encodedConstructorArguments = new hre.ethers.utils.Interface(artifact.abi)
    .encodeDeploy(constructorArguments)
    .slice(2);

  const submission = await explorerPost(chainId, apiKey, {
    action: "verifysourcecode",
    contractaddress: address,
    sourceCode: input.json,
    codeformat: "solidity-standard-json-input",
    contractname: contract,
    compilerversion: input.compilerVersion,
    constructorArguements: encodedConstructorArguments, // Etherscan's spelling
  });
  const guid = text(submission.result);
  if (alreadyVerified(submission.result)) {
    console.log(`The contract ${address} has already been verified on the block explorer.`);
    return { status: "verified" };
  }
  if (submission.status !== "1" || !guid) {
    throw new Error(
      `Explorer rejected the verification of ${address}: ${
        text(submission.result) ?? submission.message ?? "unknown error"
      }`,
    );
  }
  console.log(`Submitted ${contract} at ${address} for verification (guid ${guid})`);

  const verification = await explorerGet(chainId, apiKey, { action: "checkverifystatus", guid });
  const result = text(verification.result) ?? verification.message ?? "unknown status";
  if (verification.status === "1" && result === "Pass - Verified") {
    console.log(`Contract ${address} is verified.`);
    return { status: "verified" };
  }
  if (alreadyVerified(result)) {
    console.log(`Contract ${address} is verified.`);
    return { status: "verified" };
  }
  if (result === "Pending in queue") return { status: "queued", guid };
  throw new Error(`Explorer could not verify ${address}: ${result}`);
};
