import { baseChainData } from "../../../../config/chainData/baseData";
import { units } from "../../../testHelpers";
import { velodromeCLNonfungiblePositionGuardTest } from "../../common/velodromeCL/VelodromeNonfungiblePositionGuardTest";
import { clGaugeContractGuardCommonTest } from "../../common/velodromeCL/CLGaugeContractGuardCommonTest";
import { velodromeCLAssetGuardTest } from "../../common/velodromeCL/VelodromeCLAssetGuardTest";
import { velodromeCLMultiplePositionTest } from "../../common/velodromeCL/VelodromeCLMultiplePositionTest";

const { assets, assetsBalanceOfSlot } = baseChainData;

const testParams = [
  {
    ...baseChainData,
    ...baseChainData.aerodromeCL,
    protocolToken: baseChainData.aerodrome.aero,
    VARIABLE_PROTOCOLTOKEN_USDC: baseChainData.aerodrome.VARIABLE_AERO_USDC,
    pairs: {
      bothSupportedPair: {
        tickSpacing: 100,
        token0: assets.weth,
        token1: assets.usdc,
        amount0: units(1, 18),
        amount1: units(4000, 6),
        token0Slot: assetsBalanceOfSlot.weth,
        token1Slot: assetsBalanceOfSlot.usdc,
        token0PriceFeed: baseChainData.usdPriceFeeds.eth,
        token1PriceFeed: baseChainData.usdPriceFeeds.usdc,
        gauge: "0xF33a96b5932D9E9B9A0eDA447AbD8C9d48d2e0c8",
      },
      token0UnsupportedPair: {
        tickSpacing: 1,
        token0: assets.dai,
        token1: assets.usdc,
        amount0: units(3000),
        amount1: units(3000, 6),
      },
      token1UnsupportedPair: {
        tickSpacing: 1,
        token0: assets.usdc,
        token1: assets.dai,
        amount0: units(3000, 6),
        amount1: units(3000),
      },
    },
  },
  {
    ...baseChainData,
    ...baseChainData.aerodromeCL,
    protocolToken: baseChainData.aerodrome.aero,
    VARIABLE_PROTOCOLTOKEN_USDC: baseChainData.aerodrome.VARIABLE_AERO_USDC,
    pairs: {
      bothSupportedPair: {
        tickSpacing: 1,
        token0: assets.usdc,
        token1: assets.usdbc,
        amount0: units(4000, 6),
        amount1: units(4000, 6),
        token0Slot: assetsBalanceOfSlot.usdc,
        token1Slot: assetsBalanceOfSlot.usdbc,
        token0PriceFeed: baseChainData.usdPriceFeeds.usdc,
        token1PriceFeed: baseChainData.usdPriceFeeds.usdbc,
        gauge: "0x4a3E1294d7869567B387FC3d5e5Ccf14BE2Bbe0a",
      },
      token0UnsupportedPair: {
        tickSpacing: 100,
        token0: assets.weth,
        token1: assets.usdc,
        amount0: units(1, 18).div(100),
        amount1: units(3000, 6),
      },
      token1UnsupportedPair: {
        tickSpacing: 100,
        token0: assets.usdc,
        token1: assets.weth,
        amount0: units(3000, 6),
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
