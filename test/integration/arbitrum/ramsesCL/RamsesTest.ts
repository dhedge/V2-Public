import { arbitrumChainData } from "../../../../config/chainData/arbitrumData";
import { AssetType } from "../../../../deployment/upgrade/jobs/assetsJob";
import { units } from "../../../testHelpers";
import { IRamsesCLTestParams } from "./deploymentTestHelpers";
import { ramsesCLAssetGuardTest } from "./RamsesCLAssetGuardTest";
import { ramsesCLNonfungiblePositionGuardTest } from "./RamsesNonfungiblePositionGuardTest";

const { assets, assetsBalanceOfSlot } = arbitrumChainData;

const testParams: IRamsesCLTestParams[] = [
  {
    ...arbitrumChainData,
    factory: arbitrumChainData.ramsesCL.ramsesV2Factory,
    voter: arbitrumChainData.ramses.voter,
    nonfungiblePositionManager: arbitrumChainData.ramsesCL.nonfungiblePositionManager,
    protocolToken: arbitrumChainData.assets.ram,
    rewardTokenSettings: [
      {
        rewardToken: assets.arb,
        linkedAssetTypes: [AssetType["Ramses CL NFT Position Asset"]],
        underlyingAssetType: AssetType["Lending Enable Asset"],
      },
    ],
    rewardTokensPriceFeeds: [arbitrumChainData.usdPriceFeeds.arb],
    pairs: {
      bothSupportedPair: {
        fee: 50,
        tickSpacing: 1,
        token0: assets.wsteth,
        token1: assets.weth,
        amount0: units(1, 18),
        amount1: units(1, 18),
        token0Slot: assetsBalanceOfSlot.wsteth,
        token1Slot: assetsBalanceOfSlot.weth,
        token0PriceFeed: "0x478D8f26013184D7eEE8184dCB757E741a3C7EC1", //  publish oracle
        token1PriceFeed: arbitrumChainData.usdPriceFeeds.eth,
      },
    },
  },
  {
    ...arbitrumChainData,
    factory: arbitrumChainData.ramsesCL.ramsesV2Factory,
    voter: arbitrumChainData.ramses.voter,
    nonfungiblePositionManager: arbitrumChainData.ramsesCL.nonfungiblePositionManager,
    protocolToken: arbitrumChainData.assets.ram,
    rewardTokenSettings: [
      {
        rewardToken: assets.arb,
        linkedAssetTypes: [AssetType["Ramses CL NFT Position Asset"]],
        underlyingAssetType: AssetType["Lending Enable Asset"],
      },
    ],
    rewardTokensPriceFeeds: [arbitrumChainData.usdPriceFeeds.arb],
    pairs: {
      bothSupportedPair: {
        fee: 500,
        tickSpacing: 10,
        token0: assets.weth,
        token1: assets.usdcNative,
        amount0: units(1, 6),
        amount1: units(4000, 18),
        token0Slot: assetsBalanceOfSlot.weth,
        token1Slot: assetsBalanceOfSlot.usdcNative,
        token0PriceFeed: arbitrumChainData.usdPriceFeeds.eth,
        token1PriceFeed: arbitrumChainData.usdPriceFeeds.usdc,
      },
      token0UnsupportedPair: {
        fee: 500,
        token0: assets.wbtc,
        token1: assets.weth,
        amount0: units(1, 8),
        amount1: units(22, 18),
        token0Slot: assetsBalanceOfSlot.wbtc,
        token1Slot: assetsBalanceOfSlot.weth,
      },
      token1UnsupportedPair: {
        fee: 500,
        token0: assets.usdcNative,
        token1: assets.usdt,
        amount0: units(10, 6),
        amount1: units(10, 18),
        token0Slot: assetsBalanceOfSlot.wbtc,
        token1Slot: assetsBalanceOfSlot.usdcNative,
      },
    },
  },
];

testParams.forEach((params) => {
  ramsesCLNonfungiblePositionGuardTest(params);
  ramsesCLAssetGuardTest(params);
});
