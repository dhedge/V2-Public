import { launchZeroExSwapsTests } from "../../common/zeroEx/ZeroExSwapsTest";
import { arbitrumChainData } from "../../../../config/chainData/arbitrumData";

launchZeroExSwapsTests({
  ...arbitrumChainData,
  zeroEx: {
    exchangeProxy: arbitrumChainData.zeroEx.exchangeProxy,
    baseURL: "https://arbitrum.api.0x.org/",
    nativeTokenTicker: "ETH",
  },
  usdtAddress: arbitrumChainData.assets.usdt,
  usdtPriceFeed: arbitrumChainData.usdPriceFeeds.usdt,
});
