import { testAaveV3WithWETH } from "../../common/aaveV3/AaveV3TestWithWETH";
import { baseChainData } from "../../../../config/chainData/baseData";

testAaveV3WithWETH({
  ...baseChainData,
  ...baseChainData.aaveV3,
  assets: {
    ...baseChainData.assets,
    dai: baseChainData.assets.usdbc,
  },
  usdPriceFeeds: {
    ...baseChainData.usdPriceFeeds,
    dai: baseChainData.usdPriceFeeds.usdbc,
  },
  assetsBalanceOfSlot: {
    ...baseChainData.assetsBalanceOfSlot,
    dai: baseChainData.assetsBalanceOfSlot.usdbc,
    usdt: baseChainData.assetsBalanceOfSlot.usdbc,
  },
  aTokens: {
    ...baseChainData.aaveV3.aTokens,
    dai: baseChainData.aaveV3.aTokens.usdbc,
    usdt: baseChainData.aaveV3.aTokens.usdbc,
  },
  variableDebtTokens: {
    ...baseChainData.aaveV3.variableDebtTokens,
    dai: baseChainData.aaveV3.variableDebtTokens.usdbc,
  },
  velodromeV2: {
    factory: baseChainData.aerodrome.factory,
    router: baseChainData.aerodrome.router,
  },
});
