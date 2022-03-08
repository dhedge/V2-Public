import { assets, assetsBalanceOfSlot, uniswapV3 } from "../../../config/chainData/polygon-data";
import { units } from "../../TestHelpers";
import { UniswapV3AssetGuardTest } from "../common/UniswapV3AssetGuardTest";

UniswapV3AssetGuardTest(
  "polygon",
  uniswapV3,
  {
    fee: 500,
    token0: assets.usdc,
    token1: assets.usdt,
    amount0: units(2000, 6),
    amount1: units(2000, 6),
    token0Slot: assetsBalanceOfSlot.usdc,
    token1Slot: assetsBalanceOfSlot.usdt,
  },
  {
    fee: 3000,
    token0: assets.wbtc,
    token1: assets.dai,
    amount0: units(1, 8).div(100),
    amount1: units(400),
    token0Slot: assetsBalanceOfSlot.wbtc,
    token1Slot: assetsBalanceOfSlot.dai,
  },
  {
    fee: 3000,
    token0: assets.wbtc,
    token1: assets.usdc,
    amount0: units(1, 8).div(100),
    amount1: units(400, 6),
    token0Slot: assetsBalanceOfSlot.wbtc,
    token1Slot: assetsBalanceOfSlot.usdc,
  },
  {
    fee: 3000,
    token0: assets.weth,
    token1: assets.dai,
    amount0: units(1),
    amount1: units(2000),
    token0Slot: assetsBalanceOfSlot.weth,
    token1Slot: assetsBalanceOfSlot.dai,
  },
);
