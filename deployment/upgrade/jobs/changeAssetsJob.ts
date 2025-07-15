import { HardhatRuntimeEnvironment } from "hardhat/types";
import { IJob, IAddresses, IUpgradeConfig, IVersions, IFileNames } from "../../types";
import { proposeTransactions } from "../../deploymentHelpers";
import type { MetaTransactionData } from "../../deploymentHelpers";

const ASSET_ADDRESS_TO_REMOVE = "";

const VAULTS_TO_REMOVE_FROM: string[] = [];

export const changeAssetsJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  _: IVersions,
  __: IFileNames,
  addresses: IAddresses,
) => {
  console.log("Running Change Assets Job...");

  if (!ASSET_ADDRESS_TO_REMOVE) return console.warn("No asset address to remove provided!");

  if (!VAULTS_TO_REMOVE_FROM.length) return console.warn("No vaults to remove asset from provided!");

  const ethers = hre.ethers;

  const assetContract = await ethers.getContractAt("contracts/interfaces/IERC20.sol:IERC20", ASSET_ADDRESS_TO_REMOVE);

  const transactionsList = await Promise.all(
    VAULTS_TO_REMOVE_FROM.map<Promise<MetaTransactionData | undefined>>(async (vaultAddress) => {
      const poolLogicContract = await ethers.getContractAt("PoolLogic", vaultAddress);
      const poolManagerLogicContractAddress = await poolLogicContract.poolManagerLogic();
      const poolManagerLogicContract = await ethers.getContractAt("PoolManagerLogic", poolManagerLogicContractAddress);
      const isSupported = await poolManagerLogicContract.isSupportedAsset(ASSET_ADDRESS_TO_REMOVE);
      const balance = await assetContract.balanceOf(vaultAddress);

      if (isSupported && balance.eq(0)) {
        return {
          to: poolManagerLogicContractAddress,
          value: "0",
          data: poolManagerLogicContract.interface.encodeFunctionData("changeAssets", [[], [ASSET_ADDRESS_TO_REMOVE]]),
        };
      }
    }),
  );

  const safeTransactionData = transactionsList.filter((txData): txData is MetaTransactionData => txData !== undefined);

  if (config.execute && safeTransactionData.length !== 0) {
    await proposeTransactions(safeTransactionData, "Change assets", config, addresses);
  } else {
    console.log("Safe transaction data: ", safeTransactionData);
  }
};
