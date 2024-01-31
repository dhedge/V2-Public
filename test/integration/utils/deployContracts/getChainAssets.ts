import { ethers } from "hardhat";
import Decimal from "decimal.js";
import { PoolFactory } from "../../../../types";
import { polygonChainData } from "../../../../config/chainData/polygonData";
import { ovmChainData } from "../../../../config/chainData/ovmData";
import { NETWORK, IAssetSetting } from "./deployContracts";

export const deployBalancerV2LpAggregator = async (poolFactory: PoolFactory, pool: string) => {
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
      poolFactory.address,
    );
    await velodromeWethUsdcAggregator.deployed();

    const velodromeWethUsdcV2Aggregator = await VelodromeVariableLPAggregator.deploy(
      ovmChainData.velodromeV2.VARIABLE_WETH_USDC.poolAddress,
      poolFactory.address,
    );
    await velodromeWethUsdcV2Aggregator.deployed();

    const VelodromeStableLPAggregator = await ethers.getContractFactory("VelodromeStableLPAggregator");
    const velodromeUsdcDaiAggregator = await VelodromeStableLPAggregator.deploy(
      ovmChainData.velodrome.STABLE_USDC_DAI.poolAddress,
      poolFactory.address,
    );
    await velodromeUsdcDaiAggregator.deployed();

    const velodromeUsdcDaiV2Aggregator = await VelodromeStableLPAggregator.deploy(
      ovmChainData.velodromeV2.STABLE_USDC_DAI.poolAddress,
      poolFactory.address,
    );
    await velodromeUsdcDaiV2Aggregator.deployed();

    const VelodromeTWAPAggregator = await ethers.getContractFactory("VelodromeTWAPAggregator");
    const velodromeTwapAggregator = await VelodromeTWAPAggregator.deploy(
      ovmChainData.velodrome.VARIABLE_VELO_USDC.poolAddress,
      ovmChainData.velodrome.velo,
      ovmChainData.assets.usdc,
      ovmChainData.usdPriceFeeds.usdc,
    );
    await velodromeTwapAggregator.deployed();

    const VelodromeV2TWAPAggregator = await ethers.getContractFactory("VelodromeV2TWAPAggregator");
    const velodromeV2TwapAggregator = await VelodromeV2TWAPAggregator.deploy(
      ovmChainData.velodromeV2.VARIABLE_VELO_USDC.poolAddress,
      ovmChainData.velodromeV2.velo,
      ovmChainData.assets.usdc,
      ovmChainData.usdPriceFeeds.usdc,
    );
    await velodromeV2TwapAggregator.deployed();

    return [
      assetSetting(ovmChainData.assets.usdt, 0, ovmChainData.usdPriceFeeds.usdt),
      assetSetting(ovmChainData.assets.wbtc, 0, ovmChainData.usdPriceFeeds.btc),
      assetSetting(ovmChainData.assets.op, 0, ovmChainData.usdPriceFeeds.op),
      assetSetting(ovmChainData.velodrome.velo, 0, velodromeTwapAggregator.address),
      assetSetting(ovmChainData.velodromeV2.velo, 0, velodromeV2TwapAggregator.address),
      assetSetting(ovmChainData.assets.snxProxy, 1, ovmChainData.usdPriceFeeds.snx),
      assetSetting(ovmChainData.assets.susd, 1, ovmChainData.usdPriceFeeds.susd),
      assetSetting(ovmChainData.assets.slink, 1, ovmChainData.usdPriceFeeds.link),
      assetSetting(ovmChainData.assets.seth, 1, ovmChainData.usdPriceFeeds.eth),
      assetSetting(ovmChainData.aaveV3.lendingPool, 3, usdPriceAggregator.address),
      assetSetting(ovmChainData.assets.weth, 4, ovmChainData.usdPriceFeeds.eth),
      assetSetting(ovmChainData.assets.dai, 4, ovmChainData.usdPriceFeeds.dai),
      assetSetting(ovmChainData.assets.usdc, 4, ovmChainData.usdPriceFeeds.usdc),
      assetSetting(ovmChainData.uniswapV3.nonfungiblePositionManager, 7, usdPriceAggregator.address),
      assetSetting(ovmChainData.stargate.pools.susdc.address, 16, ovmChainData.usdPriceFeeds.usdc),
      assetSetting(ovmChainData.velodrome.VARIABLE_WETH_USDC.poolAddress, 15, velodromeWethUsdcAggregator.address),
      assetSetting(ovmChainData.velodrome.STABLE_USDC_DAI.poolAddress, 15, velodromeUsdcDaiAggregator.address),
      assetSetting(ovmChainData.velodromeV2.VARIABLE_WETH_USDC.poolAddress, 25, velodromeWethUsdcV2Aggregator.address),
      assetSetting(ovmChainData.velodromeV2.STABLE_USDC_DAI.poolAddress, 25, velodromeUsdcDaiV2Aggregator.address),
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
      assetSetting(polygonChainData.assets.wmatic, 0, polygonChainData.usdPriceFeeds.matic),
      assetSetting(polygonChainData.assets.usdt, 0, polygonChainData.usdPriceFeeds.usdt),
      assetSetting(polygonChainData.assets.sushi, 0, polygonChainData.usdPriceFeeds.sushi),
      assetSetting(polygonChainData.assets.balancer, 0, polygonChainData.usdPriceFeeds.balancer),
      assetSetting(polygonChainData.assets.miMatic, 0, polygonChainData.usdPriceFeeds.miMatic),
      assetSetting(polygonChainData.assets.stMatic, 0, polygonChainData.usdPriceFeeds.stMatic),
      assetSetting(polygonChainData.assets.tusd, 0, polygonChainData.usdPriceFeeds.tusd),
      assetSetting(polygonChainData.aaveV2.lendingPool, 3, usdPriceAggregator.address),
      assetSetting(polygonChainData.assets.weth, 4, polygonChainData.usdPriceFeeds.eth),
      assetSetting(polygonChainData.assets.dai, 4, polygonChainData.usdPriceFeeds.dai),
      assetSetting(polygonChainData.assets.link, 4, polygonChainData.usdPriceFeeds.link),
      assetSetting(polygonChainData.assets.usdc, 4, polygonChainData.usdPriceFeeds.usdc),
      assetSetting(polygonChainData.assets.quick, 4, polygonChainData.usdPriceFeeds.quick),
      assetSetting(polygonChainData.uniswapV3.nonfungiblePositionManager, 7, usdPriceAggregator.address),
      assetSetting(polygonChainData.aaveV3.lendingPool, 8, usdPriceAggregator.address),
      assetSetting(polygonChainData.balancer.gaugePools.stMATIC.gauge, 10, usdPriceAggregator.address),
      assetSetting(polygonChainData.balancer.gaugePools.maticX.gauge, 10, usdPriceAggregator.address),
      assetSetting(polygonChainData.stargate.pools.susdc.address, 16, polygonChainData.usdPriceFeeds.usdc),
      assetSetting(polygonChainData.stargate.pools.sdai.address, 16, polygonChainData.usdPriceFeeds.dai),
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
