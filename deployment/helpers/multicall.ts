import { Contract, providers } from "ethers";

// Multicall3 is deployed at the same address on every supported EVM chain.
export const MULTICALL3_ADDRESS = "0xcA11bde05977b3631167028862bE2a173976CA11";

export const MULTICALL3_ABI = [
  "function aggregate3(tuple(address target, bool allowFailure, bytes callData)[] calls) view returns (tuple(bool success, bytes returnData)[])",
];

// Default sub-calls per aggregate3 request. Chunks run sequentially, so a large
// network (hundreds of reads) becomes a handful of requests instead of one giant fan-out.
export const MULTICALL_CHUNK_SIZE = 200;

export interface Aggregate3Call {
  target: string;
  allowFailure: boolean;
  callData: string;
}

export interface Multicall3Result {
  success: boolean;
  returnData: string;
}

// Build a Multicall3 contract instance bound to the given provider.
export const getMulticall3 = (provider: providers.Provider): Contract =>
  new Contract(MULTICALL3_ADDRESS, MULTICALL3_ABI, provider);

// Run aggregate3 over `calls` in sequential chunks and concatenate the results.
export const aggregate3InChunks = async (
  multicall: Contract,
  calls: Aggregate3Call[],
  chunkSize: number = MULTICALL_CHUNK_SIZE,
): Promise<Multicall3Result[]> => {
  const results: Multicall3Result[] = [];
  for (let i = 0; i < calls.length; i += chunkSize) {
    const batch: Multicall3Result[] = await multicall.aggregate3(calls.slice(i, i + chunkSize));
    results.push(...batch);
  }
  return results;
};
