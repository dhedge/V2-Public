import { launchZeroExSwapsTests } from "../../common/zeroEx/ZeroExSwapsTest";
import { polygonChainData } from "../../../../config/chainData/polygonData";

launchZeroExSwapsTests({
  assets: {
    weth: polygonChainData.assets.weth,
    usdc: polygonChainData.assets.usdc,
    usdt: polygonChainData.assets.usdt,
    dai: polygonChainData.assets.dai,
  },
  usdPriceFeeds: {
    eth: polygonChainData.usdPriceFeeds.eth,
    usdc: polygonChainData.usdPriceFeeds.usdc,
    usdt: polygonChainData.usdPriceFeeds.usdt,
    dai: polygonChainData.usdPriceFeeds.dai,
  },
  assetsBalanceOfSlot: {
    usdc: polygonChainData.assetsBalanceOfSlot.usdc,
  },
  zeroEx: {
    exchangeProxy: polygonChainData.zeroEx.exchangeProxy,
    baseURL: "https://polygon.api.0x.org",
    nativeTokenTicker: "MATIC",
  },
});
