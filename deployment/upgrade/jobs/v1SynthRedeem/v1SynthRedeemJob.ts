import { IERC20 } from "../../../../types";
import { IJob } from "../../../types";
import DHedgeV1VaultABI from "./DHedge.json";
import { V1_VAULTS_FROM_BACKEND_SORTED_BY_TVL_DESC_WITH_SETH_OR_SBTC } from "./v1VaultsFromBackend";
import { proposeTransactions } from "../../../deploymentHelpers";
import type { MetaTransactionData } from "../../../deploymentHelpers";

const IERC20_PATH = "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20";

const sETH_ADDRESS = "0x5e74c9036fb86bd7ecdcb084a0673efc32ea31cb";
const sBTC_ADDRESS = "0xfe18be6b3bd88a2d2a7f928d00292e7a9963cfc6";

export const v1SynthRedeemJob: IJob<void> = async (config, hre, _, __, addresses) => {
  const ethers = hre.ethers;
  const IDHedgeV1Vault = new ethers.utils.Interface(DHedgeV1VaultABI);

  const sETH = <IERC20>await ethers.getContractAt(IERC20_PATH, sETH_ADDRESS);
  const sBTC = <IERC20>await ethers.getContractAt(IERC20_PATH, sBTC_ADDRESS);

  const sETHBytes32 = ethers.utils.formatBytes32String("sETH");
  const sBTCBytes32 = ethers.utils.formatBytes32String("sBTC");
  const sUSDBytes32 = ethers.utils.formatBytes32String("sUSD");

  const transactionsList = await Promise.all(
    V1_VAULTS_FROM_BACKEND_SORTED_BY_TVL_DESC_WITH_SETH_OR_SBTC.map<Promise<MetaTransactionData[]>>(async (address) => {
      const vault = await ethers.getContractAt(DHedgeV1VaultABI, address);
      const transactions: MetaTransactionData[] = [];

      const sETHVaultBalance = await sETH.balanceOf(address);
      if (sETHVaultBalance.gt(0)) {
        transactions.push({
          to: address,
          value: "0",
          data: IDHedgeV1Vault.encodeFunctionData("exchange", [sETHBytes32, sETHVaultBalance, sUSDBytes32]),
        });
      }
      const sETHEnabled = await vault.isAssetSupported(sETHBytes32);
      if (sETHEnabled) {
        transactions.push({
          to: address,
          value: "0",
          data: IDHedgeV1Vault.encodeFunctionData("removeFromSupportedAssets", [sETHBytes32]),
        });
      }

      const sBTCVaultBalance = await sBTC.balanceOf(address);
      if (sBTCVaultBalance.gt(0)) {
        transactions.push({
          to: address,
          value: "0",
          data: IDHedgeV1Vault.encodeFunctionData("exchange", [sBTCBytes32, sBTCVaultBalance, sUSDBytes32]),
        });
      }
      const sBTCEnabled = await vault.isAssetSupported(sBTCBytes32);
      if (sBTCEnabled) {
        transactions.push({
          to: address,
          value: "0",
          data: IDHedgeV1Vault.encodeFunctionData("removeFromSupportedAssets", [sBTCBytes32]),
        });
      }

      return transactions;
    }),
  );

  const safeTransactionData = transactionsList.flat();

  console.log("safeTransactionData", safeTransactionData);

  await proposeTransactions(safeTransactionData, "V1 Synths Redeem", config, addresses);
};
