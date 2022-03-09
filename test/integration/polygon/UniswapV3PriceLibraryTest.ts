import { assets, uniswapV3 } from "../../../config/chainData/polygon-data";
import { IV3AssetPair, uniswapV3PriceLibraryTest } from "../common/UniswapV3PriceLibraryTest";

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
];

uniswapV3PriceLibraryTest({
  network: "polygon",
  uniswapV3Factory: uniswapV3.factory,
  assetPairs,
});

// assetSetting(polygonData.assets.wmatic, 0, polygonData.price_feeds.matic),
// assetSetting(polygonData.assets.usdt, 0, polygonData.price_feeds.usdt),
// assetSetting(polygonData.assets.sushi, 0, polygonData.price_feeds.sushi),
// assetSetting(polygonData.assets.balancer, 0, polygonData.price_feeds.balancer),
// assetSetting(polygonData.assets.miMatic, 0, polygonData.price_feeds.matic),
// assetSetting(polygonData.assets.tusd, 0, polygonData.price_feeds.tusd),
// assetSetting(polygonData.aave.lendingPool, 3, usdPriceAggregator.address),
// assetSetting(polygonData.assets.weth, 4, polygonData.price_feeds.eth),
// assetSetting(polygonData.assets.dai, 4, polygonData.price_feeds.dai),
// assetSetting(polygonData.assets.usdc, 4, polygonData.price_feeds.usdc),
// assetSetting(polygonData.uniswapV3.nonfungiblePositionManager, 7, usdPriceAggregator.address),
// assetSushiLPWethUsdc,
// assetQuickLPWethUsdc,
// balancerLpAsset,
// balancerLpAssetWethBalancer,
