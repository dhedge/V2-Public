import { ovmChainData } from "../../../config/chainData/ovm-data";
const { assets, assetsBalanceOfSlot, uniswapV3 } = ovmChainData;
import { units } from "../../TestHelpers";
import { uniswapV3AssetGuardTest } from "../common/UniswapV3AssetGuardTest";

uniswapV3AssetGuardTest({
  network: "ovm",
  uniswapV3,
  pairs: {
    bothSupportedPair: {
      fee: 500,
      token0: assets.usdc,
      token1: assets.usdt,
      amount0: units(2000, 6),
      amount1: units(2000, 6),
      token0Slot: assetsBalanceOfSlot.usdc,
      token1Slot: assetsBalanceOfSlot.usdt,
    },
    bothUnsupportedPair: {
      fee: 3000,
      token0: assets.wbtc,
      token1: assets.dai,
      amount0: units(1, 8).div(100),
      amount1: units(400),
      token1Slot: 2,
    },
    token0UnsupportedPair: {
      fee: 3000,
      token0: assets.wbtc,
      token1: assets.usdc,
      amount0: units(1, 8).div(100),
      amount1: units(400, 6),
    },
    bothSupportedNonStablePair: {
      fee: 3000,
      token0: assets.weth,
      token1: assets.usdc,
      amount0: units(1),
      amount1: units(2900, 6),
      token0Slot: assetsBalanceOfSlot.weth,
      token1Slot: assetsBalanceOfSlot.usdc,
    },
  },
});
