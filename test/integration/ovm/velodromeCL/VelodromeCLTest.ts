import { ovmChainData } from "../../../../config/chainData/ovmData";
import { units } from "../../../testHelpers";
import { velodromeCLNonfungiblePositionGuardTest } from "../../common/velodromeCL/VelodromeNonfungiblePositionGuardTest";
import { clGaugeContractGuardCommonTest } from "../../common/velodromeCL/CLGaugeContractGuardCommonTest";
import { velodromeCLAssetGuardTest } from "../../common/velodromeCL/VelodromeCLAssetGuardTest";
import { velodromeCLMultiplePositionTest } from "../../common/velodromeCL/VelodromeCLMultiplePositionTest";

const { assets, assetsBalanceOfSlot } = ovmChainData;

const testParams = [
  {
    ...ovmChainData,
    ...ovmChainData.velodromeCL,
    protocolToken: ovmChainData.velodromeV2.velo,
    VARIABLE_PROTOCOLTOKEN_USDC: ovmChainData.velodromeV2.VARIABLE_VELO_USDC,
    pairs: {
      bothSupportedPair: {
        tickSpacing: 100,
        token0: assets.usdcNative,
        token1: assets.weth,
        amount0: units(1, 18),
        amount1: units(4000, 18),
        token0Slot: assetsBalanceOfSlot.usdcNative,
        token1Slot: assetsBalanceOfSlot.weth,
        token0PriceFeed: ovmChainData.usdPriceFeeds.usdc,
        token1PriceFeed: ovmChainData.usdPriceFeeds.eth,
        gauge: "0xa75127121d28a9BF848F3B70e7Eea26570aa7700",
      },
      token0UnsupportedPair: {
        tickSpacing: 1,
        token0: assets.dai,
        token1: assets.usdcNative,
        amount0: units(3000),
        amount1: units(3000, 6),
      },
      token1UnsupportedPair: {
        tickSpacing: 1,
        token0: assets.usdcNative,
        token1: assets.susd,
        amount0: units(3000, 6),
        amount1: units(3000),
      },
    },
  },
  {
    ...ovmChainData,
    ...ovmChainData.velodromeCL,
    protocolToken: ovmChainData.velodromeV2.velo,
    VARIABLE_PROTOCOLTOKEN_USDC: ovmChainData.velodromeV2.VARIABLE_VELO_USDC,
    pairs: {
      bothSupportedPair: {
        tickSpacing: 1,
        token0: assets.usdcNative,
        token1: assets.usdt,
        amount0: units(1, 18),
        amount1: units(4000, 18),
        token0Slot: assetsBalanceOfSlot.usdcNative,
        token1Slot: assetsBalanceOfSlot.usdt,
        token0PriceFeed: ovmChainData.usdPriceFeeds.usdc,
        token1PriceFeed: ovmChainData.usdPriceFeeds.usdt,
        gauge: "0xC762d18800B3f78ae56E9e61aD7BE98a413D59dE",
      },
      token0UnsupportedPair: {
        tickSpacing: 100,
        token0: assets.usdc,
        token1: assets.weth,
        amount0: units(3000, 6),
        amount1: units(1, 18).div(100),
      },
      token1UnsupportedPair: {
        tickSpacing: 1,
        token0: assets.usdt,
        token1: assets.lusd,
        amount0: units(1, 18).div(100),
        amount1: units(1, 18).div(100),
      },
    },
  },
];

testParams.forEach((params) => {
  velodromeCLNonfungiblePositionGuardTest(params);
  clGaugeContractGuardCommonTest(params);
  velodromeCLAssetGuardTest(params);
  velodromeCLMultiplePositionTest(params);
});
