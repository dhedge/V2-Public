import { testAaveV3 } from "../../common/aaveV3/AaveV3Test";
import { testAaveV3Multiple } from "../../common/aaveV3/AaveV3TestMultiple";
import { ovmChainData } from "../../../../config/chainData/ovmData";

const testParams = {
  ...ovmChainData,
  ...ovmChainData.aaveV3,
  usdPriceFeeds: {
    ...ovmChainData.usdPriceFeeds,
    borrowAsset: ovmChainData.usdPriceFeeds.dai,
  },
  assetsBalanceOfSlot: {
    ...ovmChainData.assetsBalanceOfSlot,
    borrowAsset: ovmChainData.assetsBalanceOfSlot.dai,
  },
  borrowAsset: ovmChainData.assets.dai,
  swapper: ovmChainData.flatMoney.swapper,
  chainId: 10,
} as const;

testAaveV3(testParams);
testAaveV3Multiple(testParams);
