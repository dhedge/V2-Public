import { HardhatRuntimeEnvironment } from "hardhat/types";
import { SafeService } from "@safe-global/safe-ethers-adapters";
import Safe, { EthersAdapter } from "@safe-global/protocol-kit";
import { MetaTransactionData } from "@safe-global/safe-core-sdk-types";

import { IERC20 } from "../../../../types";
import { IJob } from "../../../types";
import DHedgeV1VaultABI from "./DHedge.json";
import { V1_VAULTS_FROM_BACKEND_SORTED_BY_TVL_DESC_WITH_SETH_OR_SBTC } from "./v1VaultsFromBackend";

const IERC20_PATH = "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20";

const SAFE_API_URL_MAINNET = "https://safe-transaction-mainnet.safe.global";
const SAFE_ADDRESS_MAINNET = "0x5a76f841bFe5182f04bf511fC0Ecf88C27189FCB";

const sETH_ADDRESS = "0x5e74c9036fb86bd7ecdcb084a0673efc32ea31cb";
const sBTC_ADDRESS = "0xfe18be6b3bd88a2d2a7f928d00292e7a9963cfc6";

const proposeTx = async (hre: HardhatRuntimeEnvironment, safeTransactionData: MetaTransactionData[]) => {
  const ethers = hre.ethers;
  const provider = ethers.provider;
  const signer = provider.getSigner(0);
  const ethAdapter = new EthersAdapter({ ethers, signerOrProvider: signer });
  const safeSdk = await Safe.create({
    ethAdapter,
    safeAddress: SAFE_ADDRESS_MAINNET,
  });
  const safeTransaction = await safeSdk.createTransaction({ safeTransactionData });
  console.log("safeTransaction", safeTransaction);
  const txHash = await safeSdk.getTransactionHash(safeTransaction);
  const service = new SafeService(SAFE_API_URL_MAINNET);
  const signature = await safeSdk.signTransactionHash(txHash);
  await service.proposeTx(SAFE_ADDRESS_MAINNET, txHash, safeTransaction, signature);
};

export const v1SynthRedeemJob: IJob<void> = async (_, hre: HardhatRuntimeEnvironment) => {
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

  await proposeTx(hre, safeTransactionData);
};
