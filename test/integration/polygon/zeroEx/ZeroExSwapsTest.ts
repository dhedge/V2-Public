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
    eth: polygonChainData.price_feeds.eth,
    usdc: polygonChainData.price_feeds.usdc,
    usdt: polygonChainData.price_feeds.usdt,
    dai: polygonChainData.price_feeds.dai,
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
