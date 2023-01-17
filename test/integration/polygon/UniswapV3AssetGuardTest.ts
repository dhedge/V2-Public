import { polygonChainData } from "../../../config/chainData/polygon-data";
const { assets, assetsBalanceOfSlot, uniswapV3 } = polygonChainData;
import { units } from "../../TestHelpers";
import { uniswapV3AssetGuardTest } from "../common/UniswapV3AssetGuardTest";

uniswapV3AssetGuardTest({
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
    bothUnsupportedPair: {
      fee: 500,
      token0: assets.frax,
      token1: assets.miMatic,
      amount0: units(1),
      amount1: units(1),
    },
    token0UnsupportedPair: {
      fee: 500,
      token0: assets.xsgd,
      token1: assets.weth,
      amount0: units(1),
      amount1: units(1),
    },
    bothSupportedNonStablePair: {
      fee: 3000,
      token0: assets.weth,
      token1: assets.dai,
      amount0: units(1),
      amount1: units(2000),
      token0Slot: assetsBalanceOfSlot.weth,
      token1Slot: assetsBalanceOfSlot.dai,
    },
  },
});
