import { uniswapV3SwapRouterGuardTest } from "../../common/uniswapV3/UniswapV3SwapRouterGuardTest";
import { units } from "../../../testHelpers";
import { polygonChainData } from "../../../../config/chainData/polygonData";

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
  noDirectPoolPair: {
    tokenIn: assets.weth,
    tokenIntermediate: assets.usdc,
    tokenOut: assets.link,
    amountInMax: units(1, 18),
    amountOut: units(1, 18),
    tokenInSlot: assetsBalanceOfSlot.weth,
  },
});
