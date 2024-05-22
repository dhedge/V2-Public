import { testAaveV3 } from "../../common/aaveV3/AaveV3Test";
import { baseChainData } from "../../../../config/chainData/baseData";

// Switching usdt to usdbc because usdt is not in aave and on Base in general
testAaveV3({
  ...baseChainData,
  ...baseChainData.aaveV3,
  assets: {
    ...baseChainData.assets,
    usdt: baseChainData.assets.usdbc,
  },
  usdPriceFeeds: {
    ...baseChainData.usdPriceFeeds,
    usdt: baseChainData.usdPriceFeeds.usdbc,
  },
  assetsBalanceOfSlot: {
    ...baseChainData.assetsBalanceOfSlot,
    usdt: baseChainData.assetsBalanceOfSlot.usdbc,
  },
  aTokens: {
    ...baseChainData.aaveV3.aTokens,
    usdt: baseChainData.aaveV3.aTokens.usdbc,
  },
  variableDebtTokens: {
    ...baseChainData.aaveV3.variableDebtTokens,
  },
  velodromeV2: {
    factory: baseChainData.aerodrome.factory,
    router: baseChainData.aerodrome.router,
  },
});
