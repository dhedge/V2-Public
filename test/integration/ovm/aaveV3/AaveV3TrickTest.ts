import { AaveV3TrickTest } from "../../common/aaveV3/AaveV3TrickTest";
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

AaveV3TrickTest(testParams);
