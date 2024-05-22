import { launchZeroExSwapsTests } from "../../common/zeroEx/ZeroExSwapsTest";
import { ovmChainData } from "../../../../config/chainData/ovmData";

launchZeroExSwapsTests({
  ...ovmChainData,
  zeroEx: {
    exchangeProxy: ovmChainData.zeroEx.exchangeProxy,
    baseURL: "https://optimism.api.0x.org",
    nativeTokenTicker: "ETH",
  },
  usdtAddress: ovmChainData.assets.usdt,
  usdtPriceFeed: ovmChainData.usdPriceFeeds.usdt,
});
