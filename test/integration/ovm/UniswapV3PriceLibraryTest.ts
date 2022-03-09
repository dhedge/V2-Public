import { assets, uniswapV3 } from "../../../config/chainData/ovm-data";
import { IV3AssetPair, uniswapV3PriceLibraryTest } from "../common/UniswapV3PriceLibraryTest";

const assetPairs: IV3AssetPair[] = [
  {
    fee: 500,
    token0: assets.usdc,
    token1: assets.usdt,
  },
  {
    fee: 500,
    token0: assets.weth,
    token1: assets.usdc,
  },
  {
    fee: 500,
    token0: assets.dai,
    token1: assets.usdc,
  },
];

uniswapV3PriceLibraryTest({
  network: "ovm",
  uniswapV3Factory: uniswapV3.factory,
  assetPairs,
});
