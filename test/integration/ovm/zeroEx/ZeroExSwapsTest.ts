import { launchZeroExSwapsTests } from "../../common/zeroEx/ZeroExSwapsTest";
import { ovmChainData } from "../../../../config/chainData/ovmData";

launchZeroExSwapsTests({
  assets: {
    weth: ovmChainData.assets.weth,
    usdc: ovmChainData.assets.usdc,
    usdt: ovmChainData.assets.usdt,
    dai: ovmChainData.assets.dai,
  },
  usdPriceFeeds: {
    eth: ovmChainData.price_feeds.eth,
    usdc: ovmChainData.price_feeds.usdc,
    usdt: ovmChainData.price_feeds.usdt,
    dai: ovmChainData.price_feeds.dai,
  },
  assetsBalanceOfSlot: {
    usdc: ovmChainData.assetsBalanceOfSlot.usdc,
  },
  zeroEx: {
    exchangeProxy: ovmChainData.zeroEx.exchangeProxy,
    baseURL: "https://optimism.api.0x.org",
    nativeTokenTicker: "ETH",
  },
});
