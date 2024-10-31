import { runOneInchV6GuardTest } from "../../common/oneInch/OneInchV6GuardTest";
import { ovmChainData } from "../../../../config/chainData/ovmData";

runOneInchV6GuardTest({
  ...ovmChainData,
  chainId: 10,
  aggregationRouterV6: ovmChainData.oneinch.v6Router,
  uniV2Factory: ovmChainData.uniswapV2.factory,
  uniV3Factory: ovmChainData.uniswapV3.factory,
  assetsOptimism: {
    snx: {
      address: ovmChainData.assets.snxProxy,
      priceFeed: ovmChainData.usdPriceFeeds.snx,
      proxy: ovmChainData.synthetix.SNXProxy_target_tokenState,
      balanceOfSlot: ovmChainData.assetsBalanceOfSlot.snx,
    },
    susd: { address: ovmChainData.assets.susd, priceFeed: ovmChainData.usdPriceFeeds.susd },
  },
});
