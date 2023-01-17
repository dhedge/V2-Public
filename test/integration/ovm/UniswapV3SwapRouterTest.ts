import { units } from "../../TestHelpers";
import { ovmChainData } from "../../../config/chainData/ovm-data";
const { assets, assetsBalanceOfSlot, uniswapV3 } = ovmChainData;
import { uniswapV3SwapRouterGuardTest } from "../common/UniswapV3SwapRouterGuardTest";

uniswapV3SwapRouterGuardTest({
  network: "ovm",
  uniswapV3,
  pair: {
    fee: 500,
    token0: assets.usdc,
    token1: assets.usdt,
    amount0: units(2000, 6),
    amount1: units(2000, 6),
    token0Slot: assetsBalanceOfSlot.usdc,
    token1Slot: assetsBalanceOfSlot.usdt,
  },
});
