import { testAaveV3 } from "../../common/aaveV3/AaveV3Test";
import { testAaveV3Multiple } from "../../common/aaveV3/AaveV3TestMultiple";
import { arbitrumChainData } from "../../../../config/chainData/arbitrumData";

const testParams = {
  ...arbitrumChainData,
  ...arbitrumChainData.aaveV3,
  usdPriceFeeds: {
    ...arbitrumChainData.usdPriceFeeds,
    borrowAsset: arbitrumChainData.usdPriceFeeds.dai,
  },
  assetsBalanceOfSlot: {
    ...arbitrumChainData.assetsBalanceOfSlot,
    borrowAsset: arbitrumChainData.assetsBalanceOfSlot.dai,
  },
  borrowAsset: arbitrumChainData.assets.dai,
  swapper: arbitrumChainData.flatMoney.swapper,
  chainId: 42161,
} as const;

testAaveV3(testParams);
testAaveV3Multiple(testParams);
