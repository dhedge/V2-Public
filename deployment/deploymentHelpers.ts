import fs from "fs";
import util from "util";
import axios from "axios";
import { exec } from "child_process";
import { Input } from "csv-stringify";
import stringify from "csv-stringify/lib/sync";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { SafeService } from "@safe-global/safe-ethers-adapters";
import Safe, { EthersAdapter, ContractNetworksConfig } from "@safe-global/protocol-kit";
import { IProposeTxProperties, IUpgradeConfigProposeTx } from "./types";
import { retryWithDelay } from "./utils";

const execProm = util.promisify(exec);

let nonce: number;

export const nonceLog: {
  nonce: number;
  message: string;
}[] = [];

export const getTag = async () => {
  try {
    await execProm("git pull --tags");
  } catch {}
  const result = await execProm("git tag | sort -V | tail -1");
  return result.stdout.trim();
};

export const hasDuplicates = <T extends Record<string, unknown>>(array: T[], keyCreator: (v: T) => string) => {
  const valueArr = array
    .map(keyCreator)
    .filter(Boolean)
    .map((x) => x.toLowerCase());

  const dups = valueArr.filter((item, index) => valueArr.indexOf(item) !== index);

  if (dups.length) {
    console.log("Duplicates", dups);
    return true;
  } else {
    return false;
  }
};

export const isSameBytecode = (creationBytecode: string, runtimeBytecode: string) => {
  const bytecodeB = runtimeBytecode.substring(39);
  const bytecodeSnippet = bytecodeB.substring(0, 100);
  const indexOfSnippet = creationBytecode.indexOf(bytecodeSnippet);

  if (indexOfSnippet < 0) return false;
  const bytecodeA = creationBytecode.substring(indexOfSnippet);
  if (bytecodeA.length !== bytecodeB.length) return false;

  // Ignore the bytecode metadata https://docs.soliditylang.org/en/v0.7.6/metadata.html
  const metadataString = "a264"; // Note: this string might change in future compiler versions
  if (
    bytecodeA.substring(0, bytecodeA.indexOf(metadataString)) !==
    bytecodeB.substring(0, bytecodeB.indexOf(metadataString))
  )
    return false;

  return true;
};

export const tryVerify = async (
  hre: HardhatRuntimeEnvironment,
  address: string,
  path: string,
  constructorArguments: unknown[],
) => {
  await retryWithDelay(
    async () => {
      try {
        await hre.run("verify:verify", {
          address: address,
          contract: path,
          constructorArguments: constructorArguments,
        });
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
      } catch (e: any) {
        if (e.message.toLowerCase().includes("constructor arguments exceeds max accepted")) {
          // This error may be to do with the compiler, "constructor arguments exceeds max accepted (10k chars) length"
          // Possibly because the contract should have been compiled in isolation before deploying ie "compile:one"
          console.warn(`Couldn't verify contract at ${address}. Error: ${e.message}, skipping verification`);
          return;
        }
        if (!e.message.toLowerCase().includes("already verified")) {
          throw e;
        }
      }
    },
    "Try Verify Failed: " + address,
    10,
  );
};

export const writeCsv = (data: Input, fileName: string) => {
  const output = stringify(data, { header: true });
  fs.writeFileSync(fileName, output);
};

/// Converts a string into a hex representation of bytes32
export const toBytes32 = (key: string) => {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const { ethers } = require("hardhat");
  return ethers.utils.formatBytes32String(key);
};

const getNonce = async (
  safeSdk: Safe,
  chainId: number,
  safeAddress: string,
  restartFromLastConfirmedNonce: boolean,
  useNonce: number | undefined,
) => {
  if (useNonce !== undefined) {
    return useNonce;
  }
  const lastConfirmedNonce = await safeSdk.getNonce();
  if (restartFromLastConfirmedNonce) {
    console.log("GetNonce: Starting from LAST CONFIRMED NONCE: ", lastConfirmedNonce);
    return lastConfirmedNonce;
  }

  const safeTxApi = `https://safe-client.safe.global/v1/chains/${chainId}/safes/${safeAddress}/transactions/queued`;
  const response = await axios.get(safeTxApi);
  const results = response.data.results.reverse();
  const last = results.find((r: { type: string }) => r.type === "TRANSACTION");
  if (!last) {
    console.log("GetNonce: No Pending Nonce - Starting from LAST CONFIRMED NONCE: ", lastConfirmedNonce);
    return lastConfirmedNonce;
  }

  const nonce = last.transaction.executionInfo.nonce + 1;
  console.log("GetNonce: Starting from last PENDING nonce: ", nonce);
  return nonce;
};

export const proposeTx = async (
  to: string,
  data: string,
  message: string,
  config: IUpgradeConfigProposeTx,
  addresses: IProposeTxProperties,
) => {
  if (!config.execute) {
    console.log("Will propose transaction:", message);
    return;
  }

  // Initialize the Safe SDK
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const { ethers } = require("hardhat");
  const provider = ethers.provider;
  const owner1 = provider.getSigner(0);
  const ethAdapter = new EthersAdapter({ ethers, signerOrProvider: owner1 });
  const chainId = await ethAdapter.getChainId();

  if (!addresses.gnosisApi || !addresses.gnosisMultiSendAddress) {
    await owner1.sendTransaction({
      from: owner1.getAddress(),
      to: to,
      data: data,
    });
    return;
  }

  const service = new SafeService(addresses.gnosisApi);

  // NOTE: The following is only required in case we want to use custom deployed Safe contracts.
  // This is a workaround for Base instead of updating Safe packages to latest which obviously include Base.
  // Attempt to upgrade Safe packages led to `__classPrivateFieldGet(...).getBytes is not a function` error during `await safeSdk.signTransactionHash(txHash)` execution.
  // I suspect this might be because we are using ethers v5 version (or maybe not). Anyway it's worth to give a try and update packages again some time later.
  const contractNetworks: ContractNetworksConfig | undefined =
    chainId === 8453
      ? {
          [8453]: {
            multiSendAddress: addresses.gnosisMultiSendAddress,
            safeMasterCopyAddress: "0xfb1bffC9d739B8D520DaF37dF666da4C687191EA",
            safeProxyFactoryAddress: "0xC22834581EbC8527d974F8a1c97E1bEA4EF910BC",
            multiSendCallOnlyAddress: "0xA1dabEF33b3B82c7814B6D82A79e50F4AC44102B",
            fallbackHandlerAddress: "0x017062a1dE2FE6b99BE3d9d37841FeD19F573804",
            signMessageLibAddress: "0x98FFBBF51bb33A056B08ddf711f289936AafF717",
            createCallAddress: "0xB19D6FFc2182150F8Eb585b79D4ABcd7C5640A9d",
          },
        }
      : undefined;

  const chainSafeAddress: string = addresses.protocolDaoAddress;

  // If we want to use custom deployment of Safe contracts, we need to add `contractNetworks` argument at the end.
  const safeSdk = await Safe.create({
    ethAdapter,
    safeAddress: chainSafeAddress,
    contractNetworks,
  });

  nonce = nonce
    ? nonce
    : await retryWithDelay(
        () => getNonce(safeSdk, chainId, chainSafeAddress, config.restartnonce, config.useNonce),
        "Gnosis Get Nonce",
      );

  const safeTransactionData = {
    to: to,
    value: "0",
    data: data,
    nonce: nonce,
  };

  const log = {
    nonce: nonce,
    message: message,
  };

  console.log("Proposing transaction: ", safeTransactionData);
  console.log(`Nonce Log`, log);
  nonceLog.push(log);

  nonce += 1;

  const safeTransaction = await safeSdk.createTransaction({ safeTransactionData });
  // off-chain sign
  const txHash = await safeSdk.getTransactionHash(safeTransaction);
  const signature = await safeSdk.signTransactionHash(txHash);
  // on-chain sign
  // const approveTxResponse = await safeSdk.approveTransactionHash(txHash)
  // console.log("approveTxResponse", approveTxResponse);
  console.log("safeTransaction: ", safeTransaction);

  await retryWithDelay(() => service.proposeTx(chainSafeAddress, txHash, safeTransaction, signature), "Gnosis safe");
};

export const executeInSeries = <T>(providers: (() => Promise<T>)[]): Promise<T[]> => {
  const ret: Promise<void> = Promise.resolve(undefined);
  const results: T[] = [];

  const reduced = providers.reduce((result, provider, index) => {
    const x = result.then(function () {
      return provider().then(function (val) {
        results[index] = val;
      });
    });
    return x;
  }, ret as Promise<void>);
  return reduced.then(() => results);
};
