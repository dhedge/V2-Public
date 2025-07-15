import { ovmChainData as chainData } from "../../../../config/chainData/ovmData";
import { units } from "../../../testHelpers";
import { compoundV3CommonTest } from "../../common/compound/CompoundV3CommonTest";

const { assets, assetsBalanceOfSlot } = chainData;

const commonParams = {
  rewards: chainData.compoundV3.rewards,
  easySwapperV2: {
    swapper: chainData.flatMoney.swapper,
    wrappedNativeToken: chainData.assets.weth,
  },
};

const testParams = [
  {
    ...chainData,
    assetName: "USDC",
    cAsset: chainData.compoundV3.cUSDCv3,
    baseAsset: assets.usdcNative,
    baseAssetSlot: assetsBalanceOfSlot.usdcNative,
    baseAssetAmount: units(100, 6),
    cAssetPriceFeed: chainData.usdPriceFeeds.usdc,
    ...commonParams,
  },
  {
    ...chainData,
    assetName: "WETH",
    cAsset: chainData.compoundV3.cWETHv3,
    baseAsset: assets.weth,
    baseAssetSlot: assetsBalanceOfSlot.weth,
    baseAssetAmount: units(1, 18),
    cAssetPriceFeed: chainData.usdPriceFeeds.eth,
    ...commonParams,
  },
  {
    ...chainData,
    assetName: "USDT",
    cAsset: chainData.compoundV3.cUSDTv3,
    baseAsset: assets.usdt,
    baseAssetSlot: assetsBalanceOfSlot.usdt,
    baseAssetAmount: units(10_000, 6),
    cAssetPriceFeed: chainData.usdPriceFeeds.usdt,
    ...commonParams,
  },
];

testParams.forEach(compoundV3CommonTest);
