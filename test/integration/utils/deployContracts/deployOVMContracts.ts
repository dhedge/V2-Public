import { ethers, upgrades } from "hardhat";
import { AssetHandler, PoolFactory, PoolPerformance } from "../../../../types";
import { toBytes32 } from "../../../TestHelpers";
import { assets, price_feeds, uniswapV3 } from "../../../../config/chainData/ovm-data";
import { Deployments } from ".";

export const deployOVMContracts = async (): Promise<Deployments> => {
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
  const assetWeth = { asset: assets.weth, assetType: 0, aggregator: price_feeds.eth };
  const assetUsdt = { asset: assets.usdt, assetType: 0, aggregator: price_feeds.usdt };
  const assetUsdc = { asset: assets.usdc, assetType: 0, aggregator: price_feeds.usdc }; // Lending enabled
  const assetNFTPosition = {
    asset: uniswapV3.nonfungiblePositionManager,
    assetType: 7,
    aggregator: usdPriceAggregator.address,
  };

  const assetHandlerInitAssets = [assetWeth, assetUsdt, assetUsdc, assetNFTPosition];

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

  const ERC20Guard = await ethers.getContractFactory("ERC20Guard");
  const erc20Guard = await ERC20Guard.deploy();
  await erc20Guard.deployed();

  const OpenAssetGuard = await ethers.getContractFactory("OpenAssetGuard");
  const openAssetGuard = await OpenAssetGuard.deploy([]);
  await openAssetGuard.deployed();

  const UniswapV3RouterGuard = await ethers.getContractFactory("UniswapV3RouterGuard");
  const uniswapV3RouterGuard = await UniswapV3RouterGuard.deploy(10, 100); // set slippage 10%
  await uniswapV3RouterGuard.deployed();

  const UniswapV3AssetGuard = await ethers.getContractFactory("UniswapV3AssetGuard");
  const uniV3AssetGuard = await UniswapV3AssetGuard.deploy(uniswapV3.nonfungiblePositionManager);
  await uniV3AssetGuard.deployed();

  const UniswapV3NonfungiblePositionGuard = await ethers.getContractFactory("UniswapV3NonfungiblePositionGuard");
  const uniswapV3NonfungiblePositionGuard = await UniswapV3NonfungiblePositionGuard.deploy(
    uniswapV3.nonfungiblePositionManager,
    1,
  );
  await uniswapV3NonfungiblePositionGuard.deployed();

  await governance.setAssetGuard(0, erc20Guard.address);
  await governance.setAssetGuard(6, erc20Guard.address); // set balancer lp asset guard to normal erc20 guard
  await governance.setAssetGuard(7, uniV3AssetGuard.address);
  await governance.setContractGuard(uniswapV3.router, uniswapV3RouterGuard.address);
  await governance.setContractGuard(uniswapV3.nonfungiblePositionManager, uniswapV3NonfungiblePositionGuard.address);

  await governance.setAddresses([
    { name: toBytes32("weth"), destination: assets.weth },
    { name: toBytes32("openAssetGuard"), destination: openAssetGuard.address },
  ]);

  await poolFactory.setExitFee(5, 1000); // 0.5%

  const USDT = await ethers.getContractAt("IERC20", assets.usdt);
  const USDC = await ethers.getContractAt("IERC20", assets.usdc);
  const WETH = await ethers.getContractAt("IERC20", assets.weth);

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
    assets: {
      USDT,
      USDC,
      WETH,
    },
  };
};
