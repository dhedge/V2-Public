import { execTransactionsTest } from "../common/ExecTransactionsTest";
import { polygonChainData } from "../../../config/chainData/polygonData";

execTransactionsTest({
  network: "polygon",
  oneInchRouterAddress: polygonChainData.oneinch.v5Router,
  usdc: {
    address: polygonChainData.assets.usdc,
  },
  usdt: {
    address: polygonChainData.assets.usdt,
    balanceOfSlot: polygonChainData.assetsBalanceOfSlot.usdt,
  },
  weth: {
    address: polygonChainData.assets.weth,
  },
});
