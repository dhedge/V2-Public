import { units } from "../../TestHelpers";
import { ovmChainData } from "../../../config/chainData/ovm-data";
const { assets, assetsBalanceOfSlot, uniswapV3 } = ovmChainData;
import { uniswapV3NonfungiblePositionGuardTest } from "../common/UniswapV3NonfungiblePositionGuardTest";

uniswapV3NonfungiblePositionGuardTest({
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
    token0UnsupportedPair: {
      fee: 3000,
      token0: assets.wbtc,
      token1: assets.usdc,
      amount0: units(1, 8).div(100),
      amount1: units(400, 6),
    },
    token1UnsupportedPair: {
      fee: 3000,
      token0: assets.usdc,
      token1: assets.wbtc,
      amount0: units(400, 6),
      amount1: units(1, 8).div(100),
    },
  },
});
