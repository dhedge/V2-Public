import { launchPoolTokenSwapperGuardSwapsTests } from "../../common/poolTokenSwapper/PoolTokenSwapperGuardTest";
import { ovmChainData } from "../../../../config/chainData/ovmData";

launchPoolTokenSwapperGuardSwapsTests({
  assets: {
    weth: ovmChainData.assets.weth,
    usdc: ovmChainData.assets.usdc,
    usdt: ovmChainData.assets.usdt,
    dai: ovmChainData.assets.dai,
  },
  usdPriceFeeds: {
    eth: ovmChainData.usdPriceFeeds.eth,
    usdc: ovmChainData.usdPriceFeeds.usdc,
    usdt: ovmChainData.usdPriceFeeds.usdt,
    dai: ovmChainData.usdPriceFeeds.dai,
  },
  assetsBalanceOfSlot: {
    usdc: ovmChainData.assetsBalanceOfSlot.usdc,
  },
});
