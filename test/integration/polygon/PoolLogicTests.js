const { ethers, upgrades } = require("hardhat");
const { BigNumber } = ethers;
const { expect, use } = require("chai");
const { solidity } = require("ethereum-waffle");
const { units } = require("../../TestHelpers");
const { sushi, aave, assets, price_feeds } = require("../polygon-data");

use(solidity);

const oneDollar = units(1);

describe("PoolPerformance", function () {
  let USDC;
  let logicOwner, manager, dao;
  let PoolLogic;
  let assetHandler, governance, poolFactory, poolLogicProxy, poolPerformance;

  beforeEach(async function () {
    [logicOwner, manager, dao] = await ethers.getSigners();

    const AssetHandlerLogic = await ethers.getContractFactory("AssetHandler");

    const Governance = await ethers.getContractFactory("Governance");
    governance = await Governance.deploy();

    const PoolPerformance = await ethers.getContractFactory("PoolPerformance");
    poolPerformance = await upgrades.deployProxy(PoolPerformance, [aave.protocolDataProvider]);
    await poolPerformance.deployed();

    PoolLogic = await ethers.getContractFactory("PoolLogic");
    const poolLogic = await PoolLogic.deploy();

    const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
    const poolManagerLogic = await PoolManagerLogic.deploy();

    // Initialize Asset Price Consumer
    const assetWmatic = { asset: assets.wmatic, assetType: 0, aggregator: price_feeds.matic };
    const assetUsdc = { asset: assets.usdc, assetType: 0, aggregator: price_feeds.usdc };
    const assetHandlerInitAssets = [assetWmatic, assetUsdc];

    assetHandler = await upgrades.deployProxy(AssetHandlerLogic, [assetHandlerInitAssets]);
    await assetHandler.deployed();
    await assetHandler.setChainlinkTimeout((3600 * 24 * 365).toString()); // 1 year expiry

    const PoolFactory = await ethers.getContractFactory("PoolFactory");
    poolFactory = await upgrades.deployProxy(PoolFactory, [
      poolLogic.address,
      poolManagerLogic.address,
      assetHandler.address,
      dao.address,
      governance.address,
    ]);
    await poolFactory.deployed();

    await poolFactory.setPoolPerformanceAddress(poolPerformance.address);

    const ERC20Guard = await ethers.getContractFactory("ERC20Guard");
    erc20Guard = await ERC20Guard.deploy();
    erc20Guard.deployed();

    await governance.setAssetGuard(0, erc20Guard.address);

    // Setup LogicOwner with some USDC
    const IWETH = await hre.artifacts.readArtifact("IWETH");
    const WMatic = await ethers.getContractAt(IWETH.abi, assets.wmatic);
    const IERC20 = await hre.artifacts.readArtifact("IERC20");
    USDC = await ethers.getContractAt(IERC20.abi, assets.usdc);

    const IUniswapV2Router = await hre.artifacts.readArtifact("IUniswapV2Router");
    const sushiswapRouter = await ethers.getContractAt(IUniswapV2Router.abi, sushi.router);
    await WMatic.deposit({ value: units(1000) });

    // Get USDC
    await WMatic.approve(sushi.router, units(1000));
    await sushiswapRouter.swapExactTokensForTokens(
      units(500),
      0,
      [assets.wmatic, assets.usdc],
      logicOwner.address,
      Math.floor(Date.now() / 1000 + 100000000),
    );
  });

  // Checks to make sure early exit of 100% drains all assets and does not incur fee
  // we make a conventional deposit and immediately withdraw 100% of the issued tokens
  // we then deposit again and check the token price is $1 to confirm not left over assets from previous withdraw
  it("early 100% withdrawal should not incur fee when there is a fee", async () => {
    const managerFee = BigNumber.from("0"); // 0%;
    // Create the fund we're going to use for testing
    await poolFactory.createFund(false, manager.address, "Barren Wuffet", "Test Fund", "DHTF", managerFee, [
      [assets.usdc, true],
    ]);

    const funds = await poolFactory.getDeployedFunds();
    poolLogicProxy = await PoolLogic.attach(funds[0]);
    // Deposit $1 conventional way
    await USDC.approve(poolLogicProxy.address, (100e6).toString());
    await poolLogicProxy.deposit(assets.usdc, (100e6).toString());

    // Check token price is $1
    expect((await poolLogicProxy.tokenPrice()).toString()).to.equal(oneDollar.toString());

    await poolFactory.setExitCooldown(6000000);
    await poolFactory.setExitFee(10, 100); // 10%

    // 100% withdrawal
    const withdrawalAmount = await poolLogicProxy.totalSupply();

    await poolLogicProxy.withdraw(withdrawalAmount.toString());

    // Check token price has increased by the fee kept by the pool
    expect((await poolLogicProxy.tokenPrice()).toString()).to.equal("0");

    // We deposit again to make sure everything is reset
    await USDC.approve(poolLogicProxy.address, (100e6).toString());
    await poolLogicProxy.deposit(assets.usdc, (100e6).toString());

    // Check token price is $1
    expect((await poolPerformance.tokenPrice(poolLogicProxy.address)).toString()).to.equal(oneDollar.toString());
    // Check tokenPriceAdjustForPerformance == $1
    expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
      oneDollar.toString(),
    );
  });
});
