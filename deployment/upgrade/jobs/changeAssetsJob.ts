import { HardhatRuntimeEnvironment } from "hardhat/types";
import { IJob, IAddresses, IUpgradeConfig, IVersions, IFileNames } from "../../types";
import { proposeTransactions } from "../../deploymentHelpers";
import type { MetaTransactionData } from "../../deploymentHelpers";

const VAULTS_TO_REMOVE_FROM: string[] = [];

const ASSET_ADDRESSES_TO_REMOVE: string[] = [];

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

      const assetContract = await ethers.getContractAt("contracts/interfaces/IERC20.sol:IERC20", assetAddress);
      const balance = await assetContract.balanceOf(vaultAddress);
      if (!balance.eq(0)) {
        console.warn(`Skipping ${assetAddress} in vault ${vaultAddress}: non-zero balance (${balance.toString()})`);
        continue;
      }

      assetsToRemove.push(assetAddress);
    }

    if (assetsToRemove.length > 0) {
      console.log(`Vault ${vaultAddress}: removing ${assetsToRemove.length} asset(s)`);
      safeTransactionData.push({
        to: poolManagerLogicContractAddress,
        value: "0",
        data: poolManagerLogicContract.interface.encodeFunctionData("changeAssets", [[], assetsToRemove]),
      });
    }
  }

  if (config.execute && safeTransactionData.length !== 0) {
    await proposeTransactions(safeTransactionData, "Change assets", config, addresses);
  } else {
    console.log("Safe transaction data: ", safeTransactionData);
  }
};
