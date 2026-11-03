import Safe from "@safe-global/protocol-kit";
import SafeApiKit from "@safe-global/api-kit";
import { IProposeTxProperties, IUpgradeConfigProposeTx } from "../types";
import { retryWithDelay } from "./retry";
import { ChainId } from "../chainIds";

export type MetaTransactionData = Parameters<Safe["createTransactionBatch"]>[0][0];

let nonce: number;

export const nonceLog: {
  nonce: number;
  message: string;
}[] = [];

const getNonce = async (
  safeSdk: Safe,
  safeApiKit: SafeApiKit,
  safeAddress: string,
  restartFromLastConfirmedNonce: boolean,
  useNonce: number | undefined,
): Promise<number> => {
  if (useNonce !== undefined) {
    return useNonce;
  }

  if (restartFromLastConfirmedNonce) {
    const lastConfirmedNonce = await safeSdk.getNonce();
    console.log("GetNonce: Starting from LAST CONFIRMED NONCE: ", lastConfirmedNonce);
    return lastConfirmedNonce;
  }

  const nextNonce = await safeApiKit.getNextNonce(safeAddress);
  return +nextNonce;
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

export const proposeTransactions = async (
  safeTransactionData: MetaTransactionData[],
  message: string,
  config: IUpgradeConfigProposeTx,
  addresses: IProposeTxProperties,
) => {
  const chainData: Record<number, (string | undefined)[]> = {
    [ChainId.ethereum]: [process.env.ETHEREUM_URL, process.env.ETHEREUM_PRIVATE_KEY],
    [ChainId.polygon]: [process.env.POLYGON_URL, process.env.POLYGON_PRIVATE_KEY],
    [ChainId.optimism]: [process.env.OPTIMISM_URL, process.env.OVM_PRIVATE_KEY],
    [ChainId.arbitrum]: [process.env.ARBITRUM_URL, process.env.ARBITRUM_PRIVATE_KEY],
    [ChainId.base]: [process.env.BASE_URL, process.env.BASE_PRIVATE_KEY],
    [ChainId.plasma]: [
      process.env.PLASMA_URL,
      process.env.PLASMA_PRIVATE_KEY,
      "https://api.safe.global/tx-service/plasma/api",
    ],
    [ChainId.hyperevm]: [
      process.env.HYPEREVM_URL,
      process.env.HYPEREVM_PRIVATE_KEY,
      "https://api.safe.global/tx-service/hyper/api",
    ],
  };

  const [provider, signer, txServiceUrl] = chainData[config.chainId] ?? [];

  if (!provider || !signer) throw new Error("Missing provider or signer: check env vars and chainData");

  const safeAddress = addresses.protocolDaoAddress;
  const safeSdk = await Safe.init({
    signer,
    provider,
    safeAddress,
  });
  const apiKit = new SafeApiKit({
    chainId: BigInt(config.chainId),
    apiKey: process.env.SAFE_API_KEY,
    txServiceUrl,
  });

  nonce =
    nonce ??
    (await retryWithDelay(
      () => getNonce(safeSdk, apiKit, safeAddress, config.restartnonce, config.useNonce),
      "SAFE Get Nonce",
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
