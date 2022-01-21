const { ethers, upgrades } = require("hardhat");
const { expect, use } = require("chai");
const chaiAlmost = require("chai-almost");
const { checkAlmostSame, toBytes32 } = require("../../TestHelpers");
const { uniswapV3, assets, price_feeds } = require("../../../config/chainData/ethereum-data");

use(chaiAlmost());

const deadLine = Math.floor(Date.now() / 1000 + 100000000);

describe("Uniswap V3 LP Test", function () {
  let WETH, USDC, UniswapRouter;
  let logicOwner, manager, dao;
  let PoolFactory, PoolLogic, PoolManagerLogic, assetHandler;
  let poolFactory, poolLogic, poolManagerLogic, poolLogicProxy, poolManagerLogicProxy, fundAddress;
  let nonfungiblePositionManager, tokenId;

  before(async function () {
    [logicOwner, manager, dao] = await ethers.getSigners();

    nonfungiblePositionManager = await ethers.getContractAt(
      "INonfungiblePositionManager",
      uniswapV3.nonfungiblePositionManager,
    );

    const AssetHandlerLogic = await ethers.getContractFactory("AssetHandler");

    const Governance = await ethers.getContractFactory("Governance");
    let governance = await Governance.deploy();
    console.log("governance deployed to:", governance.address);

    const PoolPerformance = await ethers.getContractFactory("PoolPerformance");
    const poolPerformance = await upgrades.deployProxy(PoolPerformance);
    await poolPerformance.deployed();

    PoolLogic = await ethers.getContractFactory("PoolLogic");
    poolLogic = await PoolLogic.deploy();

    PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
    poolManagerLogic = await PoolManagerLogic.deploy();

    // Initialize Asset Price Consumer

    // Deploy USD Price Aggregator
    const USDPriceAggregator = await ethers.getContractFactory("USDPriceAggregator");
    const usdPriceAggregator = await USDPriceAggregator.deploy();

    const assetWeth = { asset: assets.weth, assetType: 0, aggregator: price_feeds.eth };
    const assetUsdt = { asset: assets.usdt, assetType: 0, aggregator: price_feeds.usdt };
    const assetUsdc = { asset: assets.usdc, assetType: 0, aggregator: price_feeds.usdc };
    const assetNFTPosition = {
      asset: uniswapV3.nonfungiblePositionManager,
      assetType: 7,
      aggregator: usdPriceAggregator.address,
    };
    const assetHandlerInitAssets = [assetWeth, assetUsdt, assetUsdc, assetNFTPosition];

    assetHandler = await upgrades.deployProxy(AssetHandlerLogic, [assetHandlerInitAssets]);
    await assetHandler.deployed();
    await assetHandler.setChainlinkTimeout((3600 * 24 * 365).toString()); // 1 year expiry

    PoolFactory = await ethers.getContractFactory("PoolFactory");
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

    const UniswapV3SwapGuard = await ethers.getContractFactory("UniswapV3SwapGuard");
    uniswapV3SwapGuard = await UniswapV3SwapGuard.deploy();
    uniswapV3SwapGuard.deployed();

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
    await governance.setAssetGuard(7, uniV3AssetGuard.address);
    await governance.setContractGuard(uniswapV3.router, uniswapV3SwapGuard.address);
    await governance.setContractGuard(uniswapV3.nonfungiblePositionManager, uniswapV3NonfungiblePositionGuard.address);
    await governance.setAddresses([
      { name: toBytes32("nonfungiblePositionManager"), destination: uniswapV3.nonfungiblePositionManager },
    ]);

    await poolFactory.setExitFee(5, 1000); // 0.5%
  });

  it("Should be able to get WETH", async function () {
    const IWETH = await hre.artifacts.readArtifact("IWETH");
    WETH = await ethers.getContractAt(IWETH.abi, assets.weth);
    const IERC20 = await hre.artifacts.readArtifact("IERC20");
    USDC = await ethers.getContractAt(IERC20.abi, assets.usdc);
    const IUniswapV3Router = await hre.artifacts.readArtifact("IUniswapV3Router");
    UniswapRouter = await ethers.getContractAt(IUniswapV3Router.abi, uniswapV3.router);
    // deposit ETH -> WETH
    await WETH.deposit({ value: (10e18).toString() });
    // WETH -> USDC
    let sourceAmount = (5e18).toString();
    await WETH.approve(uniswapV3.router, (5e18).toString());
    const exactInputSingleParams = {
      tokenIn: assets.weth,
      tokenOut: assets.usdc,
      fee: 10000,
      recipient: logicOwner.address,
      deadline: deadLine,
      amountIn: sourceAmount,
      amountOutMinimum: 0,
      sqrtPriceLimitX96: 0,
    };
    await UniswapRouter.exactInputSingle(exactInputSingleParams);
  });

  it("Should be able to createFund", async function () {
    await poolFactory.createFund(
      false,
      manager.address,
      "Barren Wuffet",
      "Test Fund",
      "DHTF",
      new ethers.BigNumber.from("5000"),
      [
        [assets.usdc, true],
        [assets.weth, true],
      ],
    );

    const deployedFunds = await poolFactory.getDeployedFunds();
    const fundAddress = deployedFunds[deployedFunds.length - 1];
    poolLogicProxy = await PoolLogic.attach(fundAddress);
    let poolManagerLogicProxyAddress = await poolLogicProxy.poolManagerLogic();
    poolManagerLogicProxy = await PoolManagerLogic.attach(poolManagerLogicProxyAddress);
  });

  it("should be able to deposit usdc/weth", async function () {
    // Approve and deposit 100 USDC
    await USDC.approve(poolLogicProxy.address, (10000e6).toString());
    await poolLogicProxy.deposit(assets.usdc, (10000e6).toString());

    // Approve and deposit 5 WETH
    await WETH.approve(poolLogicProxy.address, (5e18).toString());
    await poolLogicProxy.deposit(assets.weth, (5e18).toString());
  });

  it("Should be able to approve", async () => {
    const IERC20 = await hre.artifacts.readArtifact("IERC20");
    const iERC20 = new ethers.utils.Interface(IERC20.abi);

    // Approve to swap 100 USDC
    let approveABI = iERC20.encodeFunctionData("approve", [uniswapV3.nonfungiblePositionManager, (10000e6).toString()]);
    await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);

    // Approve to swap 1 WETH
    approveABI = iERC20.encodeFunctionData("approve", [uniswapV3.nonfungiblePositionManager, (5e18).toString()]);
    await poolLogicProxy.connect(manager).execTransaction(assets.weth, approveABI);
  });

  it("Should be able to add liquidity", async () => {
    const INonfungiblePositionManager = await hre.artifacts.readArtifact("INonfungiblePositionManager");
    const iNonfungiblePositionManager = new ethers.utils.Interface(INonfungiblePositionManager.abi);

    let mintABI = iNonfungiblePositionManager.encodeFunctionData("mint", [
      [
        assets.usdc,
        assets.weth,
        10000,
        -414400,
        -253200,
        (2000e6).toString(),
        (1e18).toString(),
        0,
        0,
        poolLogicProxy.address,
        deadLine,
      ],
    ]);

    await expect(
      poolLogicProxy.connect(manager).execTransaction(uniswapV3.nonfungiblePositionManager, mintABI),
    ).to.revertedWith("asset not enabled in pool");

    // add supported assets
    await poolManagerLogicProxy
      .connect(manager)
      .changeAssets([{ asset: uniswapV3.nonfungiblePositionManager, isDeposit: false }], []);

    const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

    await poolLogicProxy.connect(manager).execTransaction(uniswapV3.nonfungiblePositionManager, mintABI);

    checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);

    expect(await nonfungiblePositionManager.balanceOf(poolLogicProxy.address)).to.equal(1);
    tokenId = await nonfungiblePositionManager.tokenOfOwnerByIndex(poolLogicProxy.address, 0);
  });

  it("Should be able to increase liquidity", async () => {
    const positionBefore = await nonfungiblePositionManager.positions(tokenId);

    const INonfungiblePositionManager = await hre.artifacts.readArtifact("INonfungiblePositionManager");
    const iNonfungiblePositionManager = new ethers.utils.Interface(INonfungiblePositionManager.abi);

    let increaseLiquidityABI = iNonfungiblePositionManager.encodeFunctionData("increaseLiquidity", [
      [tokenId, (2000e6).toString(), (1e18).toString(), 0, 0, deadLine],
    ]);

    const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

    await poolLogicProxy.connect(manager).execTransaction(uniswapV3.nonfungiblePositionManager, increaseLiquidityABI);

    checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);

    const positionAfter = await nonfungiblePositionManager.positions(tokenId);

    expect(positionBefore.liquidity).to.lt(positionAfter.liquidity);
  });

  it("Should be able to decrease liquidity", async () => {
    const positionBefore = await nonfungiblePositionManager.positions(tokenId);

    const INonfungiblePositionManager = await hre.artifacts.readArtifact("INonfungiblePositionManager");
    const iNonfungiblePositionManager = new ethers.utils.Interface(INonfungiblePositionManager.abi);

    let decreaseLiquidityABI = iNonfungiblePositionManager.encodeFunctionData("decreaseLiquidity", [
      [tokenId, positionBefore.liquidity, 0, 0, deadLine],
    ]);

    const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

    await poolLogicProxy.connect(manager).execTransaction(uniswapV3.nonfungiblePositionManager, decreaseLiquidityABI);

    checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);

    const positionAfter = await nonfungiblePositionManager.positions(tokenId);

    expect(positionAfter.liquidity).to.equal(0);
  });

  it("Should be able to collect", async () => {
    const INonfungiblePositionManager = await hre.artifacts.readArtifact("INonfungiblePositionManager");
    const iNonfungiblePositionManager = new ethers.utils.Interface(INonfungiblePositionManager.abi);

    let collectABI = iNonfungiblePositionManager.encodeFunctionData("collect", [
      [
        tokenId,
        poolLogicProxy.address,
        (100e18).toString(), // max
        (100e18).toString(), // max
      ],
    ]);

    const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
    const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
    const wethBalanceBefore = await WETH.balanceOf(poolLogicProxy.address);

    await poolLogicProxy.connect(manager).execTransaction(uniswapV3.nonfungiblePositionManager, collectABI);

    const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
    const wethBalanceAfter = await WETH.balanceOf(poolLogicProxy.address);
    expect(usdcBalanceAfter.gt(usdcBalanceBefore) || wethBalanceAfter.gt(wethBalanceBefore)).to.true;
    checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
  });

  it("Should be able to burn", async () => {
    const INonfungiblePositionManager = await hre.artifacts.readArtifact("INonfungiblePositionManager");
    const iNonfungiblePositionManager = new ethers.utils.Interface(INonfungiblePositionManager.abi);

    let burnABI = iNonfungiblePositionManager.encodeFunctionData("burn", [tokenId]);

    const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

    await poolLogicProxy.connect(manager).execTransaction(uniswapV3.nonfungiblePositionManager, burnABI);

    checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);

    expect(await nonfungiblePositionManager.balanceOf(poolLogicProxy.address)).to.equal(0);
  });
});
