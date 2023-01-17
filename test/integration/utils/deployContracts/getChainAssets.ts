import { ethers } from "hardhat";
import Decimal from "decimal.js";
import { PoolFactory } from "../../../../types";
import { polygonChainData } from "../../../../config/chainData/polygon-data";
import { ovmChainData } from "../../../../config/chainData/ovm-data";
import { NETWORK, IAssetSetting } from "./deployContracts";

const deployBalancerV2LpAggregator = async (poolFactory: PoolFactory, pool: string) => {
  const weights: Decimal[] = (await (await ethers.getContractAt("IBalancerWeightedPool", pool)).getNormalizedWeights())
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    .map((w: any) => new Decimal(w.toString()).div(ethers.utils.parseEther("1").toString()));

  const ether = "1000000000000000000";
  const divisor = weights.reduce((acc, w, i) => {
    if (i == 0) {
      return new Decimal(w).pow(w);
    }
    return acc.mul(new Decimal(w).pow(w));
  }, new Decimal("0"));

  const K = new Decimal(ether).div(divisor).toFixed(0);

  const matrix: string[][] = [];
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

    const VelodromeVariableLPAggregator = await ethers.getContractFactory("VelodromeVariableLPAggregator");
    const velodromeWethUsdcAggregator = await VelodromeVariableLPAggregator.deploy(
      ovmChainData.velodrome.VARIABLE_WETH_USDC.poolAddress,
      ovmChainData.velodrome.factory,
    );
    await velodromeWethUsdcAggregator.deployed();
    const velodromeWethUsdcLpAsset = {
      asset: ovmChainData.velodrome.VARIABLE_WETH_USDC.poolAddress,
      assetType: 15,
      aggregator: velodromeWethUsdcAggregator.address,
    };

    const VelodromeStableLPAggregator = await ethers.getContractFactory("VelodromeStableLPAggregator");
    const velodromeUsdcDaiAggregator = await VelodromeStableLPAggregator.deploy(
      ovmChainData.velodrome.STABLE_USDC_DAI.poolAddress,
      poolFactory.address,
    );
    await velodromeUsdcDaiAggregator.deployed();
    const velodromeUsdcDaiLpAsset = {
      asset: ovmChainData.velodrome.STABLE_USDC_DAI.poolAddress,
      assetType: 15,
      aggregator: velodromeUsdcDaiAggregator.address,
    };

    const VelodromeTWAPAggregator = await ethers.getContractFactory("VelodromeTWAPAggregator");
    const velodromeTwapAggregator = await VelodromeTWAPAggregator.deploy(
      ovmChainData.velodrome.VARIABLE_VELO_USDC.poolAddress,
      ovmChainData.velodrome.velo,
      ovmChainData.assets.usdc,
      ovmChainData.price_feeds.usdc,
    );
    await velodromeTwapAggregator.deployed();
    return [
      assetSetting(ovmChainData.assets.usdt, 0, ovmChainData.price_feeds.usdt),
      assetSetting(ovmChainData.assets.wbtc, 0, ovmChainData.price_feeds.btc),
      assetSetting(ovmChainData.assets.op, 0, ovmChainData.price_feeds.op),
      assetSetting(ovmChainData.velodrome.velo, 0, velodromeTwapAggregator.address),
      assetSetting(ovmChainData.assets.snxProxy, 1, ovmChainData.price_feeds.snx),
      assetSetting(ovmChainData.assets.susd, 1, ovmChainData.price_feeds.susd),
      assetSetting(ovmChainData.assets.slink, 1, ovmChainData.price_feeds.link),
      assetSetting(ovmChainData.assets.seth, 1, ovmChainData.price_feeds.eth),
      assetSetting(ovmChainData.aaveV3.lendingPool, 3, usdPriceAggregator.address),
      assetSetting(ovmChainData.assets.weth, 4, ovmChainData.price_feeds.eth),
      assetSetting(ovmChainData.assets.dai, 4, ovmChainData.price_feeds.dai),
      assetSetting(ovmChainData.assets.usdc, 4, ovmChainData.price_feeds.usdc),
      assetSetting(ovmChainData.uniswapV3.nonfungiblePositionManager, 7, usdPriceAggregator.address),
      velodromeWethUsdcLpAsset,
      velodromeUsdcDaiLpAsset,
    ];
  } else {
    // Polygon network

    // Deploy Sushi LP Aggregators
    const UniV2LPAggregator = await ethers.getContractFactory("UniV2LPAggregator");
    const sushiLPAggregator = await UniV2LPAggregator.deploy(
      polygonChainData.sushi.pools.usdc_weth.address,
      poolFactory.address,
    );
    const assetSushiLPWethUsdc = {
      asset: polygonChainData.sushi.pools.usdc_weth.address,
      assetType: 2,
      aggregator: sushiLPAggregator.address,
    };

    // Deploy Quick LP Aggregators
    const quickLPAggregator = await UniV2LPAggregator.deploy(
      polygonChainData.quickswap.pools.usdc_weth.address,
      poolFactory.address,
    );
    const assetQuickLPWethUsdc = {
      asset: polygonChainData.quickswap.pools.usdc_weth.address,
      assetType: 5,
      aggregator: quickLPAggregator.address,
    };

    // Deploy Balancer LP Aggregators
    const BalancerComposableStablePoolAggregator = await ethers.getContractFactory(
      "BalancerComposableStablePoolAggregator",
    );
    const balancerComposableV2AggregatorStMatic = await BalancerComposableStablePoolAggregator.deploy(
      poolFactory.address,
      polygonChainData.balancer.stableComposablePools.wMaticStMatic,
    );

    await balancerComposableV2AggregatorStMatic.deployed();
    const balancerComposableStableStMaticLpAsset = {
      asset: polygonChainData.balancer.stableComposablePools.wMaticStMatic,
      assetType: 0,
      aggregator: balancerComposableV2AggregatorStMatic.address,
    };

    const balancerComposableV2AggregatorMaticX = await BalancerComposableStablePoolAggregator.deploy(
      poolFactory.address,
      polygonChainData.balancer.stableComposablePools.wMaticMaticX,
    );
    await balancerComposableV2AggregatorMaticX.deployed();
    const balancerComposableStableMaticXLpAsset = {
      asset: polygonChainData.balancer.stableComposablePools.wMaticMaticX,
      assetType: 0,
      aggregator: balancerComposableV2AggregatorMaticX.address,
    };

    const BalancerStablePoolAggregator = await ethers.getContractFactory("BalancerStablePoolAggregator");
    const balancerV2Aggregator = await BalancerStablePoolAggregator.deploy(
      poolFactory.address,
      polygonChainData.balancer.stablePools.BPSP,
    );
    await balancerV2Aggregator.deployed();
    const balancerLpAsset = {
      asset: polygonChainData.balancer.stablePools.BPSP,
      assetType: 0,
      aggregator: balancerV2Aggregator.address,
    };

    const balancerV2AggregatorWethBalancer = await deployBalancerV2LpAggregator(
      poolFactory,
      polygonChainData.balancer.pools.bal80weth20,
    );
    const balancerLpAssetWethBalancer = {
      asset: polygonChainData.balancer.pools.bal80weth20,
      assetType: 0,
      aggregator: balancerV2AggregatorWethBalancer.address,
    };

    const balancerV2AggregatorSTMATICBalancer = await BalancerStablePoolAggregator.deploy(
      poolFactory.address,
      polygonChainData.balancer.gaugePools.stMATIC.pool,
    );
    await balancerV2AggregatorSTMATICBalancer.deployed();
    const balancerLpAssetSTMATICBalancer = {
      asset: polygonChainData.balancer.gaugePools.stMATIC.pool,
      assetType: 0,
      aggregator: balancerV2AggregatorSTMATICBalancer.address,
    };

    const MaticXPriceAggregator = await ethers.getContractFactory("MaticXPriceAggregator");
    const maticXPriceAggregator = await MaticXPriceAggregator.deploy(
      polygonChainData.assets.wmatic,
      polygonChainData.assets.maticX,
      polygonChainData.maticX.maticXPool,
      poolFactory.address,
    );
    await maticXPriceAggregator.deployed();
    const maticXAsset = {
      asset: polygonChainData.assets.maticX,
      assetType: 0,
      aggregator: maticXPriceAggregator.address,
    };

    const DQUICKPriceAggregator = await ethers.getContractFactory("DQUICKPriceAggregator");
    const dQUICKPriceAggregator = await DQUICKPriceAggregator.deploy(
      polygonChainData.quickswap.dQUICK,
      polygonChainData.assets.quick,
      poolFactory.address,
    );
    await dQUICKPriceAggregator.deployed();
    const dQUICKAsset = {
      asset: polygonChainData.quickswap.dQUICK,
      assetType: 0,
      aggregator: dQUICKPriceAggregator.address,
    };
    return [
      assetSetting(polygonChainData.assets.wmatic, 0, polygonChainData.price_feeds.matic),
      assetSetting(polygonChainData.assets.usdt, 0, polygonChainData.price_feeds.usdt),
      assetSetting(polygonChainData.assets.sushi, 0, polygonChainData.price_feeds.sushi),
      assetSetting(polygonChainData.assets.balancer, 0, polygonChainData.price_feeds.balancer),
      assetSetting(polygonChainData.assets.miMatic, 0, polygonChainData.price_feeds.miMatic),
      assetSetting(polygonChainData.assets.stMatic, 0, polygonChainData.price_feeds.stMatic),
      assetSetting(polygonChainData.assets.tusd, 0, polygonChainData.price_feeds.tusd),
      assetSetting(polygonChainData.aaveV2.lendingPool, 3, usdPriceAggregator.address),
      assetSetting(polygonChainData.assets.weth, 4, polygonChainData.price_feeds.eth),
      assetSetting(polygonChainData.assets.dai, 4, polygonChainData.price_feeds.dai),
      assetSetting(polygonChainData.assets.link, 4, polygonChainData.price_feeds.link),
      assetSetting(polygonChainData.assets.usdc, 4, polygonChainData.price_feeds.usdc),
      assetSetting(polygonChainData.assets.quick, 4, polygonChainData.price_feeds.quick),
      assetSetting(polygonChainData.uniswapV3.nonfungiblePositionManager, 7, usdPriceAggregator.address),
      assetSetting(polygonChainData.aaveV3.lendingPool, 8, usdPriceAggregator.address),
      assetSetting(polygonChainData.balancer.gaugePools.stMATIC.gauge, 10, usdPriceAggregator.address),
      assetSetting(polygonChainData.balancer.gaugePools.maticX.gauge, 10, usdPriceAggregator.address),
      assetSushiLPWethUsdc,
      assetQuickLPWethUsdc,
      balancerLpAsset,
      balancerLpAssetWethBalancer,
      balancerLpAssetSTMATICBalancer,
      balancerComposableStableStMaticLpAsset,
      maticXAsset,
      dQUICKAsset,
      balancerComposableStableMaticXLpAsset,
    ];
  }
};
