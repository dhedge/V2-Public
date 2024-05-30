import { ovmChainData } from "../../../../config/chainData/ovmData";
import { units } from "../../../testHelpers";
import { velodromeCLAssetGuardTest } from "../../common/velodromeCL/VelodromeCLAssetGuardTest";
import { velodromeCLGaugeContractGuardTest } from "../../common/velodromeCL/CLGaugeVelodromeContractGuardTest";
import { velodromeCLMultiplePositionTest } from "../../common/velodromeCL/VelodromeCLMultiplePositionTest";
import { velodromeCLNonfungiblePositionGuardTest } from "../../common/velodromeCL/VelodromeNonfungiblePositionGuardTest";

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
        gauge: "0x8d8d1CdDD5960276A1CDE360e7b5D210C3387948",
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
        tickSpacing: 100,
        token0: assets.weth,
        token1: assets.dai,
        amount0: units(1, 18),
        amount1: units(4000, 18),
        token0Slot: assetsBalanceOfSlot.weth,
        token1Slot: assetsBalanceOfSlot.dai,
        token0PriceFeed: ovmChainData.usdPriceFeeds.eth,
        token1PriceFeed: ovmChainData.usdPriceFeeds.dai,
        gauge: "0xB2afdBf04c68989212DE04f9347Ea9bc649aE18b",
      },
      token0UnsupportedPair: {
        tickSpacing: 100,
        token0: assets.usdc,
        token1: assets.weth,
        amount0: units(3000, 6),
        amount1: units(1, 18).div(100),
      },
      token1UnsupportedPair: {
        tickSpacing: 100,
        token0: assets.weth,
        token1: assets.usdc,
        amount0: units(1, 18).div(100),
        amount1: units(3000, 6),
      },
    },
  },
];

testParams.forEach((params) => {
  velodromeCLNonfungiblePositionGuardTest(params);
  velodromeCLGaugeContractGuardTest(params);
  velodromeCLAssetGuardTest(params);
  velodromeCLMultiplePositionTest(params);
});
