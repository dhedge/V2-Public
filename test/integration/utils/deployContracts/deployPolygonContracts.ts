import { ethers, upgrades } from "hardhat";
import Decimal from "decimal.js";
import { AssetHandler, PoolFactory, PoolPerformance } from "../../../../types";
import { toBytes32 } from "../../../TestHelpers";
import {
  sushi,
  aave,
  assets,
  price_feeds,
  balancer,
  quickswap,
  oneinch,
  curve,
} from "../../../../config/chainData/polygon-data";
import { Deployments } from ".";

const deployBalancerV2LpAggregator = async (
  poolFactory: PoolFactory,
  info: {
    pool: string;
    poolId: string;
    tokens: string[];
    decimals: number[];
    weights: number[];
  },
) => {
  const ether = "1000000000000000000";
  const divisor = info.weights.reduce((acc, w, i) => {
    if (i == 0) {
      return new Decimal(w).pow(w);
    }
    return acc.mul(new Decimal(w).pow(w));
  }, new Decimal("0"));

  const K = new Decimal(ether).div(divisor).toFixed(0);

  let matrix = [];
  for (let i = 1; i <= 20; i++) {
    const elements = [new Decimal(10).pow(i).times(ether).toFixed(0)];
    for (let j = 0; j < info.weights.length; j++) {
      elements.push(new Decimal(10).pow(i).pow(info.weights[j]).times(ether).toFixed(0));
    }
    matrix.push(elements);
  }

  const BalancerV2LPAggregator = await ethers.getContractFactory("BalancerV2LPAggregator");
  return await BalancerV2LPAggregator.deploy(
    poolFactory.address,
    balancer.v2Vault,
    info.pool,
    info.tokens,
    info.decimals,
    info.weights.map((w) => new Decimal(w).mul(ether).toFixed(0)),
    {
      maxPriceDeviation: "50000000000000000", // maxPriceDeviation: 0.05
      K,
      powerPrecision: "100000000", // powerPrecision
      approximationMatrix: matrix, // approximationMatrix
    },
  );
};

export const deployPolygonContracts = async (): Promise<Deployments> => {
  const [logicOwner, manager, dao, user] = await ethers.getSigners();

  const AssetHandlerLogic = await ethers.getContractFactory("AssetHandler");

  const Governance = await ethers.getContractFactory("Governance");
  const governance = await Governance.deploy();

  const PoolPerformance = await ethers.getContractFactory("PoolPerformance");
  const poolPerformance = <PoolPerformance>await upgrades.deployProxy(PoolPerformance);
  await poolPerformance.deployed();
  await poolPerformance.enable();

  const PoolLogic = await ethers.getContractFactory("PoolLogic");
  const poolLogic = await PoolLogic.deploy();

  const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
  const poolManagerLogic = await PoolManagerLogic.deploy();

  // Deploy USD Price Aggregator
  const USDPriceAggregator = await ethers.getContractFactory("USDPriceAggregator");
  const usdPriceAggregator = await USDPriceAggregator.deploy();
  // Initialize Asset Price Consumer
  const assetWmatic = { asset: assets.wmatic, assetType: 0, aggregator: price_feeds.matic };
  const assetWeth = { asset: assets.weth, assetType: 0, aggregator: price_feeds.eth };
  const assetUsdt = { asset: assets.usdt, assetType: 0, aggregator: price_feeds.usdt };
  const assetSushi = { asset: assets.sushi, assetType: 0, aggregator: price_feeds.sushi };
  const assetLendingPool = { asset: aave.lendingPool, assetType: 3, aggregator: usdPriceAggregator.address };
  const assetDai = { asset: assets.dai, assetType: 4, aggregator: price_feeds.dai }; // Lending enabled
  const assetUsdc = { asset: assets.usdc, assetType: 4, aggregator: price_feeds.usdc }; // Lending enabled
  const assetBalancer = { asset: assets.balancer, assetType: 0, aggregator: price_feeds.balancer };
  const assetMiMatic = { asset: assets.miMatic, assetType: 0, aggregator: price_feeds.dai };
  const assetHandlerInitAssets = [
    assetWmatic,
    assetWeth,
    assetUsdt,
    assetDai,
    assetUsdc,
    assetSushi,
    assetBalancer,
    assetMiMatic,
    assetLendingPool,
  ];

  const assetHandler = <AssetHandler>await upgrades.deployProxy(AssetHandlerLogic, [assetHandlerInitAssets]);
  await assetHandler.deployed();
  await assetHandler.setChainlinkTimeout((3600 * 24 * 365).toString()); // 1 year expiry

  const PoolFactory = await ethers.getContractFactory("PoolFactory");
  const poolFactory = <PoolFactory>(
    await upgrades.deployProxy(PoolFactory, [
      poolLogic.address,
      poolManagerLogic.address,
      assetHandler.address,
      dao.address,
      governance.address,
    ])
  );
  await poolFactory.deployed();

  await poolFactory.setPoolPerformanceAddress(poolPerformance.address);

  // Deploy Sushi LP Aggregator
  const UniV2LPAggregator = await ethers.getContractFactory("UniV2LPAggregator");
  const sushiLPAggregator = await UniV2LPAggregator.deploy(sushi.pools.usdc_weth.address, poolFactory.address);
  const assetSushiLPWethUsdc = {
    asset: sushi.pools.usdc_weth.address,
    assetType: 2,
    aggregator: sushiLPAggregator.address,
  };
  await assetHandler.addAssets([assetSushiLPWethUsdc]);

  const quickLPAggregator = await UniV2LPAggregator.deploy(quickswap.pools.usdc_weth.address, poolFactory.address);
  const assetQuickLPWethUsdc = {
    asset: quickswap.pools.usdc_weth.address,
    assetType: 5,
    aggregator: quickLPAggregator.address,
  };
  await assetHandler.addAssets([assetQuickLPWethUsdc]);

  // Deploy Balancer LP Aggregator
  const balancerV2Aggregator = await deployBalancerV2LpAggregator(poolFactory, balancer.pools.stablePool);
  const balancerLpAsset = {
    asset: balancer.pools.stablePool.pool,
    assetType: 6,
    aggregator: balancerV2Aggregator.address,
  };
  await assetHandler.addAssets([balancerLpAsset]);

  const balancerV2AggregatorWethBalancer = await deployBalancerV2LpAggregator(poolFactory, balancer.pools.bal80weth20);
  const balancerLpAssetWethBalancer = {
    asset: balancer.pools.bal80weth20.pool,
    assetType: 6,
    aggregator: balancerV2AggregatorWethBalancer.address,
  };
  await assetHandler.addAssets([balancerLpAssetWethBalancer]);

  const ERC20Guard = await ethers.getContractFactory("ERC20Guard");
  const erc20Guard = await ERC20Guard.deploy();
  await erc20Guard.deployed();

  const OpenAssetGuard = await ethers.getContractFactory("OpenAssetGuard");
  const openAssetGuard = await OpenAssetGuard.deploy([]);
  await openAssetGuard.deployed();

  const UniswapV2RouterGuard = await ethers.getContractFactory("UniswapV2RouterGuard");
  const uniswapV2RouterGuard = await UniswapV2RouterGuard.deploy(2, 100); // set slippage 2% for testing
  await uniswapV2RouterGuard.deployed();

  const QuickStakingRewardsGuard = await ethers.getContractFactory("QuickStakingRewardsGuard");
  const quickStakingRewardsGuard = await QuickStakingRewardsGuard.deploy();
  await quickStakingRewardsGuard.deployed();

  const QuickLPAssetGuard = await ethers.getContractFactory("QuickLPAssetGuard");
  const quickLPAssetGuard = await QuickLPAssetGuard.deploy(quickswap.stakingRewardsFactory);
  await quickLPAssetGuard.deployed();

  const SushiMiniChefV2Guard = await ethers.getContractFactory("SushiMiniChefV2Guard");
  const sushiMiniChefV2Guard = await SushiMiniChefV2Guard.deploy([assets.sushi, assets.wmatic]);
  await sushiMiniChefV2Guard.deployed();

  const SushiLPAssetGuard = await ethers.getContractFactory("SushiLPAssetGuard");
  const sushiLPAssetGuard = await SushiLPAssetGuard.deploy(sushi.minichef); // initialise with Sushi staking pool Id
  await sushiLPAssetGuard.deployed();

  const AaveLendingPoolAssetGuard = await ethers.getContractFactory("AaveLendingPoolAssetGuard");
  const aaveLendingPoolAssetGuard = await AaveLendingPoolAssetGuard.deploy(aave.protocolDataProvider);
  await aaveLendingPoolAssetGuard.deployed();

  const AaveLendingPoolGuard = await ethers.getContractFactory("AaveLendingPoolGuard");
  const aaveLendingPoolGuard = await AaveLendingPoolGuard.deploy();
  await aaveLendingPoolGuard.deployed();

  const LendingEnabledAssetGuard = await ethers.getContractFactory("LendingEnabledAssetGuard");
  const lendingEnabledAssetGuard = await LendingEnabledAssetGuard.deploy();
  await lendingEnabledAssetGuard.deployed();

  const AaveIncentivesControllerGuard = await ethers.getContractFactory("AaveIncentivesControllerGuard");
  const aaveIncentivesControllerGuard = await AaveIncentivesControllerGuard.deploy(assets.wmatic);
  await aaveIncentivesControllerGuard.deployed();

  const BalancerV2Guard = await ethers.getContractFactory("BalancerV2Guard");
  const balancerV2Guard = await BalancerV2Guard.deploy(2, 100); // set slippage 2%
  await balancerV2Guard.deployed();

  const BalancerMerkleOrchardGuard = await ethers.getContractFactory("BalancerMerkleOrchardGuard");
  const balancerMerkleOrchardGuard = await BalancerMerkleOrchardGuard.deploy();
  await balancerMerkleOrchardGuard.deployed();

  const OneInchV3Guard = await ethers.getContractFactory("OneInchV3Guard");
  const oneInchV3Guard = await OneInchV3Guard.deploy(2, 100); // set slippage 2%
  await oneInchV3Guard.deployed();

  const SwapRouter = await ethers.getContractFactory("SwapRouter");
  const swapRouter = await SwapRouter.deploy([quickswap.router, sushi.router], [curve.atricrypto3.address]);
  await swapRouter.deployed();

  let curvePoolCoins: {
    curvePool: string;
    token: string;
    coinId: string;
  }[] = [];
  for (const coin of curve.atricrypto3.coins) {
    curvePoolCoins.push({ curvePool: curve.atricrypto3.address, token: coin.token, coinId: coin.coinId });
  }
  await swapRouter.setCurvePoolCoins(curvePoolCoins);

  await governance.setAssetGuard(0, erc20Guard.address);
  await governance.setAssetGuard(2, sushiLPAssetGuard.address);
  await governance.setAssetGuard(3, aaveLendingPoolAssetGuard.address);
  await governance.setAssetGuard(4, lendingEnabledAssetGuard.address);
  await governance.setAssetGuard(5, quickLPAssetGuard.address);
  await governance.setAssetGuard(6, erc20Guard.address); // set balancer lp asset guard to normal erc20 guard
  await governance.setContractGuard(quickswap.router, uniswapV2RouterGuard.address);
  await governance.setContractGuard(quickswap.pools.usdc_weth.stakingRewards, quickStakingRewardsGuard.address);
  await governance.setContractGuard(sushi.router, uniswapV2RouterGuard.address);
  await governance.setContractGuard(sushi.minichef, sushiMiniChefV2Guard.address);
  await governance.setContractGuard(aave.lendingPool, aaveLendingPoolGuard.address);
  await governance.setContractGuard(aave.incentivesController, aaveIncentivesControllerGuard.address);
  await governance.setContractGuard(balancer.v2Vault, balancerV2Guard.address);
  await governance.setContractGuard(balancer.merkleOrchard, balancerMerkleOrchardGuard.address);
  await governance.setContractGuard(oneinch.v3Router, oneInchV3Guard.address);
  await governance.setAddresses([
    { name: toBytes32("swapRouter"), destination: swapRouter.address },
    { name: toBytes32("aaveProtocolDataProvider"), destination: aave.protocolDataProvider },
    { name: toBytes32("weth"), destination: assets.weth },
    { name: toBytes32("openAssetGuard"), destination: openAssetGuard.address },
  ]);

  await poolFactory.setExitFee(5, 1000); // 0.5%

  const WMATIC = await ethers.getContractAt("IERC20", assets.wmatic);
  const USDT = await ethers.getContractAt("IERC20", assets.usdt);
  const DAI = await ethers.getContractAt("IERC20", assets.dai);
  const USDC = await ethers.getContractAt("IERC20", assets.usdc);
  const WETH = await ethers.getContractAt("IERC20", assets.weth);
  const SUSHI = await ethers.getContractAt("IERC20", assets.sushi);
  const BALANCER = await ethers.getContractAt("IERC20", assets.balancer);
  const QUICK = await ethers.getContractAt("IERC20", assets.quick);

  const SushiLPUSDCWETH = await ethers.getContractAt("IERC20", sushi.pools.usdc_weth.address);
  const QuickLPUSDCWETH = await ethers.getContractAt("IERC20", quickswap.pools.usdc_weth.address);

  const AMUSDC = await ethers.getContractAt("IERC20", aave.aTokens.usdc);
  const AMWETH = await ethers.getContractAt("IERC20", aave.aTokens.weth);

  const VariableWETH = await ethers.getContractAt("IERC20", aave.variableDebtTokens.weth);
  const VariableUSDT = await ethers.getContractAt("IERC20", aave.variableDebtTokens.usdt);

  const BALANCERLP_STABLE = await ethers.getContractAt("IERC20", balancer.pools.stablePool.pool);
  const BALANCERLP_WETH_BALANCER = await ethers.getContractAt("IERC20", balancer.pools.bal80weth20.pool);

  return {
    logicOwner,
    manager,
    dao,
    user,
    governance,
    assetHandler,
    poolFactory,
    poolLogic,
    poolManagerLogic,
    poolPerformance,
    sushiMiniChefV2Guard,
    assets: {
      WMATIC,
      USDT,
      DAI,
      USDC,
      WETH,
      SUSHI,
      QUICK,
      BALANCER,
      SushiLPUSDCWETH,
      QuickLPUSDCWETH,
      AMUSDC,
      AMWETH,
      VariableWETH,
      VariableUSDT,
      BALANCERLP_STABLE,
      BALANCERLP_WETH_BALANCER,
    },
  };
};
