import { ovmChainData } from "../../../config/chainData/ovm-data";
const { assets, uniswapV3 } = ovmChainData;
import { IV3AssetPair, uniswapV3PriceLibraryTest } from "../common/UniswapV3PriceLibraryTest";

const assetPairs: IV3AssetPair[] = [
  {
    fee: 500,
    token0: assets.usdc,
    token1: assets.usdt,
  },
  {
    fee: 500,
    token0: assets.usdc,
    token1: assets.weth,
  },
  {
    fee: 500,
    token0: assets.usdc,
    token1: assets.dai,
  },
];

uniswapV3PriceLibraryTest({
  network: "ovm",
  uniswapV3Factory: uniswapV3.factory,
  assetPairs,
});
