import { HardhatRuntimeEnvironment } from "hardhat/types";
import { IJob, IAddresses, IUpgradeConfig, IVersions, IFileNames } from "../../types";
import { proposeTransactions } from "../../deploymentHelpers";
import type { MetaTransactionData } from "../../deploymentHelpers";

const VAULTS_TO_REMOVE_FROM: string[] = [];

const ASSET_ADDRESSES_TO_REMOVE: string[] = [];

// Asset to add as deposit if removing the only deposit asset(s) would leave a vault with none
const REPLACEMENT_DEPOSIT_ASSET = "";

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

  if (config.execute && safeTransactionData.length !== 0) {
    await proposeTransactions(safeTransactionData, "Change assets", config, addresses);
  } else {
    console.log("Safe transaction data: ", safeTransactionData);
  }
};
