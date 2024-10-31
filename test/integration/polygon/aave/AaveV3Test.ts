import { testAaveV3 } from "../../common/aaveV3/AaveV3Test";
import { testAaveV3Multiple } from "../../common/aaveV3/AaveV3TestMultiple";
import { polygonChainData } from "../../../../config/chainData/polygonData";

const testParams = {
  ...polygonChainData,
  ...polygonChainData.aaveV3,
  usdPriceFeeds: {
    ...polygonChainData.usdPriceFeeds,
    borrowAsset: polygonChainData.usdPriceFeeds.dai,
  },
  assetsBalanceOfSlot: {
    ...polygonChainData.assetsBalanceOfSlot,
    borrowAsset: polygonChainData.assetsBalanceOfSlot.dai,
  },
  borrowAsset: polygonChainData.assets.dai,
};

testAaveV3(testParams);
testAaveV3Multiple(testParams);
