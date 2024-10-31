import { polygonChainData } from "../../../../config/chainData/polygonData";
const { uniswapV3, assets } = polygonChainData;
import { IV3AssetPair, uniswapV3PriceLibraryTest } from "../../common/uniswapV3/UniswapV3PriceLibraryTest";

const assetPairs: IV3AssetPair[] = [
  {
    fee: 500,
    token0: assets.usdc,
    token1: assets.usdt,
  },
  {
    fee: 3000,
    token0: assets.wmatic,
    token1: assets.usdc,
  },
  {
    fee: 500,
    token0: assets.weth,
    token1: assets.usdc,
  },
  {
    fee: 500,
    token0: assets.wmatic,
    token1: assets.wbtc,
  },
];

uniswapV3PriceLibraryTest({
  network: "polygon",
  uniswapV3Factory: uniswapV3.factory,
  assetPairs,
});
