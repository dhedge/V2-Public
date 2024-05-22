import { launchZeroExSwapsTests } from "../../common/zeroEx/ZeroExSwapsTest";
import { polygonChainData } from "../../../../config/chainData/polygonData";

launchZeroExSwapsTests({
  ...polygonChainData,
  zeroEx: {
    exchangeProxy: polygonChainData.zeroEx.exchangeProxy,
    baseURL: "https://polygon.api.0x.org",
    nativeTokenTicker: "MATIC",
  },
  usdtAddress: polygonChainData.assets.usdt,
  usdtPriceFeed: polygonChainData.usdPriceFeeds.usdt,
});
