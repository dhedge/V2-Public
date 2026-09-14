import { HardhatRuntimeEnvironment } from "hardhat/types";
import { IJob, IAddresses, IUpgradeConfig, IVersions, IFileNames } from "../../types";
import { proposeTransactions } from "../../deploymentHelpers";
import type { MetaTransactionData } from "../../deploymentHelpers";

const VAULTS_TO_REMOVE_FROM: string[] = [];

const ASSET_ADDRESSES_TO_REMOVE: string[] = [];

// Asset to add as deposit if removing the only deposit asset(s) would leave a vault with none
const REPLACEMENT_DEPOSIT_ASSET = "";

// Estimated-gas budget per Safe proposal. Each proposal executes as one MultiSend, so what matters
// is the chunk's total gas, not its action count: past 60-action chunks executing at 18M-21M gas
// (e.g. Polygon 0xbca60e6d..., 0x379179f0..., 0x051822bc...) prove ~20M is a safe envelope, while
// removal cost varies a lot per asset guard (Sushi/Arrakis ~0.3M each vs Aave V2 0.65M-1.55M each).
// Chunks are therefore packed by summing a per-call eth_estimateGas up to this budget.
const PROPOSAL_GAS_BUDGET = 20_000_000;

export const changeAssetsJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  _: IVersions,
  __: IFileNames,
  addresses: IAddresses,
) => {
  console.log("Running Change Assets Job...");

  if (!VAULTS_TO_REMOVE_FROM.length) return console.warn("No vaults to remove assets from provided!");

  if (!ASSET_ADDRESSES_TO_REMOVE.length) return console.warn("No asset addresses to remove provided!");

  const ethers = hre.ethers;

  const uniqueVaults = [...new Set(VAULTS_TO_REMOVE_FROM)];

  const safeTransactionData: MetaTransactionData[] = [];

  for (const vaultAddress of uniqueVaults) {
    const poolLogicContract = await ethers.getContractAt("PoolLogic", vaultAddress);
    const poolManagerLogicContractAddress = await poolLogicContract.poolManagerLogic();
    const poolManagerLogicContract = await ethers.getContractAt("PoolManagerLogic", poolManagerLogicContractAddress);

    const assetsToRemove: string[] = [];

    for (const assetAddress of ASSET_ADDRESSES_TO_REMOVE) {
      const isSupported = await poolManagerLogicContract.isSupportedAsset(assetAddress);
      if (!isSupported) continue;

      const balance = await poolManagerLogicContract.assetBalance(assetAddress);
      if (!balance.eq(0)) {
        console.warn(`Skipping ${assetAddress} in vault ${vaultAddress}: non-zero balance (${balance.toString()})`);
        continue;
      }

      assetsToRemove.push(assetAddress);
    }

    if (assetsToRemove.length > 0) {
      const depositAssets: string[] = await poolManagerLogicContract.getDepositAssets();
      const remainingDepositAssets = depositAssets.filter(
        (d: string) => !assetsToRemove.some((r) => r.toLowerCase() === d.toLowerCase()),
      );

      let addAssets: { asset: string; isDeposit: boolean }[] = [];

      if (remainingDepositAssets.length === 0) {
        if (!REPLACEMENT_DEPOSIT_ASSET) {
          throw new Error(
            `Vault ${vaultAddress}: removing all deposit assets but no REPLACEMENT_DEPOSIT_ASSET configured`,
          );
        }
        console.log(
          `Vault ${vaultAddress}: adding ${REPLACEMENT_DEPOSIT_ASSET} as deposit asset (last deposit removed)`,
        );
        addAssets = [{ asset: REPLACEMENT_DEPOSIT_ASSET, isDeposit: true }];
      }

      console.log(`Vault ${vaultAddress}: removing ${assetsToRemove.length} asset(s)`);
      safeTransactionData.push({
        to: poolManagerLogicContractAddress,
        value: "0",
        data: poolManagerLogicContract.interface.encodeFunctionData("changeAssets", [addAssets, assetsToRemove]),
      });
    }
  }

  if (!safeTransactionData.length) return console.log("Nothing to remove");

  // Pack proposals by estimated gas (estimated as the Safe, which passes the owner check).
  const chunks: MetaTransactionData[][] = [];
  let chunk: MetaTransactionData[] = [];
  let chunkGas = 0;
  for (const tx of safeTransactionData) {
    let gas: number;
    try {
      gas = (
        await ethers.provider.estimateGas({ from: addresses.protocolDaoAddress, to: tx.to, data: tx.data })
      ).toNumber();
    } catch (error) {
      // E.g. "cannot remove non-empty asset" from a vault whose position is not exited yet but
      // prices to a zero balance (an Aave vault with outstanding debt). Re-run after the exits.
      console.warn(`Skipping ${tx.to}: changeAssets estimate reverted (${(error as Error).message.slice(0, 120)})`);
      continue;
    }
    if (gas > PROPOSAL_GAS_BUDGET) throw new Error(`Single changeAssets to ${tx.to} estimates above the gas budget`);
    if (chunkGas + gas > PROPOSAL_GAS_BUDGET) {
      chunks.push(chunk);
      chunk = [];
      chunkGas = 0;
    }
    chunk.push(tx);
    chunkGas += gas;
  }
  if (chunk.length) chunks.push(chunk);
  if (!chunks.length) return console.log("Nothing to propose - every changeAssets estimate was skipped");
  const packedCount = chunks.reduce((acc, c) => acc + c.length, 0);
  console.log(`${packedCount} changeAssets call(s) packed into ${chunks.length} proposal(s)`);

  if (config.execute) {
    for (const [i, proposal] of chunks.entries()) {
      const chunkInfo = `${i + 1}/${chunks.length}`;
      console.log(`Proposing chunk ${chunkInfo} (${proposal.length} transaction(s))`);
      await proposeTransactions(proposal, `Change assets ${chunkInfo}`, config, addresses);
    }
  } else {
    console.log("Safe transaction data: ", safeTransactionData);
  }
};
