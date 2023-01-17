import { units } from "../../TestHelpers";
import { polygonChainData } from "../../../config/chainData/polygon-data";
const { assets, assetsBalanceOfSlot, uniswapV3 } = polygonChainData;
import { uniswapV3NonfungiblePositionGuardTest } from "../common/UniswapV3NonfungiblePositionGuardTest";

uniswapV3NonfungiblePositionGuardTest({
  network: "polygon",
  uniswapV3,
  pairs: {
    bothSupportedPair: {
      fee: 500,
      token0: assets.usdc,
      token1: assets.weth,
      amount0: units(2000, 6),
      amount1: units(1),
      token0Slot: assetsBalanceOfSlot.usdc,
      token1Slot: assetsBalanceOfSlot.weth,
    },
    token0UnsupportedPair: {
      fee: 500,
      token0: assets.miMatic,
      token1: assets.usdc,
      amount0: units(1),
      amount1: units(2000, 6),
    },
    token1UnsupportedPair: {
      fee: 500,
      token0: assets.usdc,
      token1: assets.miMatic,
      amount0: units(2000, 6),
      amount1: units(1),
    },
  },
});
