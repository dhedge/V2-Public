import { ethers, upgrades } from "hardhat";
import { PoolFactory } from "../../../../types";
import { toBytes32 } from "../../../TestHelpers";
import { sushi, aave, assets, price_feeds } from "../../polygon-data";
import { Deployments } from ".";

export const deployPolygonContracts = async (): Promise<Deployments> => {
  const [logicOwner, manager, dao, user] = await ethers.getSigners();

  const AssetHandlerLogic = await ethers.getContractFactory("AssetHandler");

  const Governance = await ethers.getContractFactory("Governance");
  const governance = await Governance.deploy();

  const PoolPerformance = await ethers.getContractFactory("PoolPerformance");
  const poolPerformance = await upgrades.deployProxy(PoolPerformance);
  await poolPerformance.deployed();

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
  const assetHandlerInitAssets = [assetWmatic, assetWeth, assetUsdt, assetDai, assetUsdc, assetSushi, assetLendingPool];

  const assetHandler = await upgrades.deployProxy(AssetHandlerLogic, [assetHandlerInitAssets]);
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

  const ERC20Guard = await ethers.getContractFactory("ERC20Guard");
  const erc20Guard = await ERC20Guard.deploy();
  await erc20Guard.deployed();

  const OpenAssetGuard = await ethers.getContractFactory("OpenAssetGuard");
  const openAssetGuard = await OpenAssetGuard.deploy([]);
  await openAssetGuard.deployed();

  const UniswapV2RouterGuard = await ethers.getContractFactory("UniswapV2RouterGuard");
  const uniswapV2RouterGuard = await UniswapV2RouterGuard.deploy(2, 100); // set slippage 2% for testing
  await uniswapV2RouterGuard.deployed();

  const SushiMiniChefV2Guard = await ethers.getContractFactory("SushiMiniChefV2Guard");
  const sushiMiniChefV2Guard = await SushiMiniChefV2Guard.deploy(assets.sushi, assets.wmatic);
  await sushiMiniChefV2Guard.deployed();

  const SushiLPAssetGuard = await ethers.getContractFactory("SushiLPAssetGuard");
  const sushiLPAssetGuard = await SushiLPAssetGuard.deploy(sushi.minichef); // initialise with Sushi staking pool Id
  await sushiLPAssetGuard.deployed();

  const AaveLendingPoolAssetGuard = await ethers.getContractFactory("AaveLendingPoolAssetGuard");
  const aaveLendingPoolAssetGuard = await AaveLendingPoolAssetGuard.deploy(aave.protocolDataProvider);
  aaveLendingPoolAssetGuard.deployed();

  const AaveLendingPoolGuard = await ethers.getContractFactory("AaveLendingPoolGuard");
  const aaveLendingPoolGuard = await AaveLendingPoolGuard.deploy();
  aaveLendingPoolGuard.deployed();

  const LendingEnabledAssetGuard = await ethers.getContractFactory("LendingEnabledAssetGuard");
  const lendingEnabledAssetGuard = await LendingEnabledAssetGuard.deploy();
  lendingEnabledAssetGuard.deployed();

  const AaveIncentivesControllerGuard = await ethers.getContractFactory("AaveIncentivesControllerGuard");
  const aaveIncentivesControllerGuard = await AaveIncentivesControllerGuard.deploy(assets.wmatic);
  aaveIncentivesControllerGuard.deployed();

  await governance.setAssetGuard(0, erc20Guard.address);
  await governance.setAssetGuard(2, sushiLPAssetGuard.address);
  await governance.setAssetGuard(3, aaveLendingPoolAssetGuard.address);
  await governance.setAssetGuard(4, lendingEnabledAssetGuard.address);
  await governance.setContractGuard(sushi.router, uniswapV2RouterGuard.address);
  await governance.setContractGuard(sushi.minichef, sushiMiniChefV2Guard.address);
  await governance.setContractGuard(aave.lendingPool, aaveLendingPoolGuard.address);
  await governance.setContractGuard(aave.incentivesController, aaveIncentivesControllerGuard.address);
  await governance.setAddresses([
    { name: toBytes32("swapRouter"), destination: sushi.router },
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
  const SushiLPUSDCWETH = await ethers.getContractAt("IERC20", sushi.pools.usdc_weth.address);
  const AMUSDC = await ethers.getContractAt("IERC20", aave.aTokens.usdc);

  return {
    logicOwner,
    manager,
    dao,
    user,
    poolLogic,
    poolManagerLogic,
    poolFactory,
    assets: {
      WMATIC,
      USDT,
      DAI,
      USDC,
      WETH,
      SUSHI,
      SushiLPUSDCWETH,
      AMUSDC,
    },
  };
};
