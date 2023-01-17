import { units } from "../../TestHelpers";
import { uniswapV3SwapRouterGuardTest } from "../common/UniswapV3SwapRouterGuardTest";

import { polygonChainData } from "../../../config/chainData/polygon-data";
const { assets, assetsBalanceOfSlot, uniswapV3 } = polygonChainData;

uniswapV3SwapRouterGuardTest({
  network: "polygon",
  uniswapV3,
  pair: {
    fee: 500,
    token0: assets.usdc,
    token1: assets.weth,
    amount0: units(2000, 6),
    amount1: units(1),
    token0Slot: assetsBalanceOfSlot.usdc,
    token1Slot: assetsBalanceOfSlot.weth,
  },
});
