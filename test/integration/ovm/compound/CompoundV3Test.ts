import { ovmChainData as chainData } from "../../../../config/chainData/ovmData";
import { units } from "../../../testHelpers";
import { compoundV3CommonTest } from "../../common/compound/CompoundV3CommonTest";

const { assets, assetsBalanceOfSlot } = chainData;

const testParams = [
  {
    ...chainData,
    assetName: "USDC",
    cAsset: chainData.compoundV3.cUSDCv3,
    baseAsset: assets.usdcNative,
    baseAssetSlot: assetsBalanceOfSlot.usdcNative,
    baseAssetAmount: units(100, 6),
    cAssetPriceFeed: chainData.usdPriceFeeds.usdc,
    rewards: chainData.compoundV3.rewards,
  },
  {
    ...chainData,
    assetName: "WETH",
    cAsset: chainData.compoundV3.cWETHv3,
    baseAsset: assets.weth,
    baseAssetSlot: assetsBalanceOfSlot.weth,
    baseAssetAmount: units(1, 18),
    cAssetPriceFeed: chainData.usdPriceFeeds.eth,
    rewards: chainData.compoundV3.rewards,
  },
];

testParams.forEach((params) => {
  compoundV3CommonTest(params);
});
