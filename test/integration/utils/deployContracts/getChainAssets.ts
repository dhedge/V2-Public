import { ethers } from "hardhat";
import Decimal from "decimal.js";
import { PoolFactory } from "../../../../types";
import * as polygonData from "../../../../config/chainData/polygon-data";
import * as ovmData from "../../../../config/chainData/ovm-data";
import { NETWORK, IAssetSetting } from ".";

const deployBalancerV2LpAggregator = async (poolFactory: PoolFactory, pool: string) => {
  const weights: Decimal[] = (
    await (await ethers.getContractAt("IBalancerWeightedPool", pool)).getNormalizedWeights()
  ).map((w) => new Decimal(w.toString()).div(ethers.utils.parseEther("1").toString()));

  const ether = "1000000000000000000";
  const divisor = weights.reduce((acc, w, i) => {
    if (i == 0) {
      return new Decimal(w).pow(w);
    }
    return acc.mul(new Decimal(w).pow(w));
  }, new Decimal("0"));

  const K = new Decimal(ether).div(divisor).toFixed(0);

  const matrix = [];
  for (let i = 1; i <= 20; i++) {
    const elements = [new Decimal(10).pow(i).times(ether).toFixed(0)];
    for (let j = 0; j < weights.length; j++) {
      elements.push(new Decimal(10).pow(i).pow(weights[j]).times(ether).toFixed(0));
    }
    matrix.push(elements);
  }

  const BalancerV2LPAggregator = await ethers.getContractFactory("BalancerV2LPAggregator");
  return await BalancerV2LPAggregator.deploy(poolFactory.address, pool, {
    maxPriceDeviation: "50000000000000000", // maxPriceDeviation: 0.05
    K,
    powerPrecision: "100000000", // powerPrecision
    approximationMatrix: matrix, // approximationMatrix
  });
};

export const assetSetting = (asset: string, assetType: number, aggregator: string) => ({
  asset,
  assetType,
  aggregator,
});

export const getChainAssets = async (poolFactory: PoolFactory, network: NETWORK): Promise<IAssetSetting[]> => {
  const USDPriceAggregator = await ethers.getContractFactory("USDPriceAggregator");
  const usdPriceAggregator = await USDPriceAggregator.deploy();

  if (network == "ovm") {
    // Optimism network
    return [
      assetSetting(ovmData.assets.usdt, 0, ovmData.price_feeds.usdt),
      assetSetting(ovmData.assets.wbtc, 0, ovmData.price_feeds.btc),
      assetSetting(ovmData.assets.snxProxy, 1, ovmData.price_feeds.snx),
      assetSetting(ovmData.assets.susd, 1, usdPriceAggregator.address),
      assetSetting(ovmData.assets.slink, 1, ovmData.price_feeds.link),
      assetSetting(ovmData.assets.seth, 1, ovmData.price_feeds.eth),
      assetSetting(ovmData.aaveV3.lendingPool, 3, usdPriceAggregator.address),
      assetSetting(ovmData.assets.weth, 4, ovmData.price_feeds.eth),
      assetSetting(ovmData.assets.dai, 4, ovmData.price_feeds.dai),
      assetSetting(ovmData.assets.usdc, 4, ovmData.price_feeds.usdc),
      assetSetting(ovmData.uniswapV3.nonfungiblePositionManager, 7, usdPriceAggregator.address),
    ];
  } else {
    // Polygon network

    // Deploy Sushi LP Aggregators
    const UniV2LPAggregator = await ethers.getContractFactory("UniV2LPAggregator");
    const sushiLPAggregator = await UniV2LPAggregator.deploy(
      polygonData.sushi.pools.usdc_weth.address,
      poolFactory.address,
    );
    const assetSushiLPWethUsdc = {
      asset: polygonData.sushi.pools.usdc_weth.address,
      assetType: 2,
      aggregator: sushiLPAggregator.address,
    };

    // Deploy Quick LP Aggregators
    const quickLPAggregator = await UniV2LPAggregator.deploy(
      polygonData.quickswap.pools.usdc_weth.address,
      poolFactory.address,
    );
    const assetQuickLPWethUsdc = {
      asset: polygonData.quickswap.pools.usdc_weth.address,
      assetType: 5,
      aggregator: quickLPAggregator.address,
    };

    // Deploy Balancer LP Aggregators
    const BalancerStablePoolAggregator = await ethers.getContractFactory("BalancerStablePoolAggregator");
    const balancerV2Aggregator = await BalancerStablePoolAggregator.deploy(
      poolFactory.address,
      polygonData.balancer.stablePools.BPSP,
    );
    await balancerV2Aggregator.deployed();
    const balancerLpAsset = {
      asset: polygonData.balancer.stablePools.BPSP,
      assetType: 0,
      aggregator: balancerV2Aggregator.address,
    };

    const balancerV2AggregatorWethBalancer = await deployBalancerV2LpAggregator(
      poolFactory,
      polygonData.balancer.pools.bal80weth20,
    );
    const balancerLpAssetWethBalancer = {
      asset: polygonData.balancer.pools.bal80weth20,
      assetType: 0,
      aggregator: balancerV2AggregatorWethBalancer.address,
    };
    return [
      assetSetting(polygonData.assets.wmatic, 0, polygonData.price_feeds.matic),
      assetSetting(polygonData.assets.usdt, 0, polygonData.price_feeds.usdt),
      assetSetting(polygonData.assets.sushi, 0, polygonData.price_feeds.sushi),
      assetSetting(polygonData.assets.balancer, 0, polygonData.price_feeds.balancer),
      assetSetting(polygonData.assets.miMatic, 0, polygonData.price_feeds.matic),
      assetSetting(polygonData.assets.tusd, 0, polygonData.price_feeds.tusd),
      assetSetting(polygonData.aaveV2.lendingPool, 3, usdPriceAggregator.address),
      assetSetting(polygonData.assets.weth, 4, polygonData.price_feeds.eth),
      assetSetting(polygonData.assets.dai, 4, polygonData.price_feeds.dai),
      assetSetting(polygonData.assets.link, 4, polygonData.price_feeds.link),
      assetSetting(polygonData.assets.usdc, 4, polygonData.price_feeds.usdc),
      assetSetting(polygonData.uniswapV3.nonfungiblePositionManager, 7, usdPriceAggregator.address),
      assetSetting(polygonData.aaveV3.lendingPool, 8, usdPriceAggregator.address),
      assetSushiLPWethUsdc,
      assetQuickLPWethUsdc,
      balancerLpAsset,
      balancerLpAssetWethBalancer,
    ];
  }
};
