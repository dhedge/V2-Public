import fs from "fs";
import util from "util";
import axios from "axios";
import { exec } from "child_process";
import { Input } from "csv-stringify";
import stringify from "csv-stringify/lib/sync";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import Safe from "@safe-global/protocol-kit";
import SafeApiKit from "@safe-global/api-kit";
import { IProposeTxProperties, IUpgradeConfigProposeTx } from "./types";
import { retryWithDelay } from "./utils";

export type MetaTransactionData = Parameters<Safe["createTransactionBatch"]>[0][0];

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

  await proposeTransactions(
    [
      {
        to,
        value: "0",
        data,
      },
    ],
    message,
    config,
    addresses,
  );
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

export const proposeTransactions = async (
  safeTransactionData: MetaTransactionData[],
  message: string,
  config: IUpgradeConfigProposeTx,
  addresses: IProposeTxProperties,
) => {
  const chainData = {
    1: [process.env.ETHEREUM_URL, process.env.ETHEREUM_PRIVATE_KEY],
    137: [process.env.POLYGON_URL, process.env.POLYGON_PRIVATE_KEY],
    10: [process.env.OPTIMISM_URL, process.env.OVM_PRIVATE_KEY],
    42161: [process.env.ARBITRUM_URL, process.env.ARBITRUM_PRIVATE_KEY],
    8453: [process.env.BASE_URL, process.env.BASE_PRIVATE_KEY],
  };

  const [provider, signer] = chainData[config.chainId] ?? [];

  if (!provider || !signer) throw new Error("Missing provider or signer: check env vars and chainData");

  const safeAddress = addresses.protocolDaoAddress;
  const safeSdk = await Safe.init({
    signer,
    provider,
    safeAddress,
  });
  const apiKit = new SafeApiKit({
    chainId: BigInt(config.chainId),
  });

  nonce =
    nonce ??
    (await retryWithDelay(
      () => getNonce(safeSdk, config.chainId, safeAddress, config.restartnonce, config.useNonce),
      "Safe Get Nonce",
    ));

  const options = {
    nonce,
  };
  const log = {
    nonce,
    message,
  };

  console.log("Proposing transaction: ", safeTransactionData);
  console.log("Nonce Log", log);
  nonceLog.push(log);

  nonce += 1;

  const safeTransaction = await safeSdk.createTransaction({
    transactions: safeTransactionData,
    options,
    onlyCalls: true,
  });
  const safeTxHash = await safeSdk.getTransactionHash(safeTransaction);
  const safeSignature = await safeSdk.signHash(safeTxHash);
  console.log("safeTransaction: ", safeTransaction);

  await retryWithDelay(
    () =>
      apiKit.proposeTransaction({
        safeAddress,
        safeTransactionData: safeTransaction.data,
        safeTxHash,
        senderAddress: safeSignature.signer,
        senderSignature: safeSignature.data,
      }),
    "SAFE Propose Transaction",
  );
};
