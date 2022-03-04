import { assets, assetsBalanceOfSlot, uniswapV3 } from "../../../config/chainData/polygon-data";
import { units } from "../../TestHelpers";
import { UniswapV3AssetGuardTest } from "../common/UniswapV3AssetGuardTest";

UniswapV3AssetGuardTest(
  "polygon",
  uniswapV3,
  {
    fee: 500,
    token0: assets.usdc,
    token1: assets.weth,
    amount0: units(2000, 6),
    amount1: units(1),
    token0Slot: assetsBalanceOfSlot.usdc,
    token1Slot: assetsBalanceOfSlot.weth,
  },
  {
    fee: 500,
    token0: assets.frax,
    token1: assets.miMatic,
    amount0: units(1),
    amount1: units(1),
  },
  {
    fee: 500,
    token0: assets.xsgd,
    token1: assets.weth,
    amount0: units(1),
    amount1: units(1),
  },
);
