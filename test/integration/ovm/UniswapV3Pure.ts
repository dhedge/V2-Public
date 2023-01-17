import { ovmChainData } from "../../../config/chainData/ovm-data";
const { assets, assetsBalanceOfSlot, uniswapV3 } = ovmChainData;
import { units } from "../../TestHelpers";
import { UniswapV3PureTest } from "../common/UniswapV3PureTest";

UniswapV3PureTest(uniswapV3, {
  fee: 500,
  token0: assets.weth,
  token1: assets.usdc,
  amount0: units(1),
  amount1: units(2900, 6),
  token0Slot: assetsBalanceOfSlot.weth,
  token1Slot: assetsBalanceOfSlot.usdc,
  token0Decimals: 18,
  token1Decimals: 6,
});
