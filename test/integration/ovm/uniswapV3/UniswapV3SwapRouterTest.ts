import { uniswapV3SwapRouterGuardTest } from "../../common/uniswapV3/UniswapV3SwapRouterGuardTest";
import { units } from "../../../testHelpers";
import { ovmChainData } from "../../../../config/chainData/ovmData";

const { assets, assetsBalanceOfSlot, uniswapV3 } = ovmChainData;

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
  noDirectPoolPair: {
    tokenIn: assets.wbtc,
    tokenIntermediate: assets.weth, // can be usdt
    tokenOut: assets.dai,
    amountInMax: units(1, 8),
    amountOut: units(1, 18),
    tokenInSlot: assetsBalanceOfSlot.wbtc,
  },
});
