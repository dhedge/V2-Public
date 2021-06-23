const { ethers, upgrades } = require("hardhat");
const { expect, use } = require("chai");
const chaiAlmost = require("chai-almost");

use(chaiAlmost());

const checkAlmostSame = (a, b) => {
  expect(ethers.BigNumber.from(a).gt(ethers.BigNumber.from(b).mul(95).div(100))).to.be.true;
  expect(ethers.BigNumber.from(a).lt(ethers.BigNumber.from(b).mul(105).div(100))).to.be.true;
};

const uniswapV2Factory = "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f";
const uniswapV2Router = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";
const sushiswapRouter = "0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F";
const sushiswapFactory = "0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac";

// For mainnet
const weth = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
const usdc = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
const usdt = "0xdAC17F958D2ee523a2206206994597C13D831ec7";
const sushi_usdc_usdt = "0xD86A120a06255Df8D4e2248aB04d4267E23aDfaA";
const eth_price_feed = "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419";
const usdt_price_feed = "0x3E7d1eAB13ad0104d2750B8863b489D65364e32D";
const usdc_price_feed = "0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6";
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

describe("Sushiswap/Uniswap V2 Test", function () {
  let WETH, USDC, USDT, SushiUsdcUsdt, UniswapRouter;
  let logicOwner, manager, dao, user;
  let PoolFactory, PoolLogic, PoolManagerLogic, assetHandler;
  let poolFactory, poolLogic, poolManagerLogic, poolLogicProxy, poolManagerLogicProxy, fundAddress;
  let uniswapV2RouterGuard, sushiswapGuard;

  before(async function () {
    [logicOwner, manager, dao, user] = await ethers.getSigners();

    const AssetHandlerLogic = await ethers.getContractFactory("AssetHandler");

    PoolLogic = await ethers.getContractFactory("PoolLogic");
    poolLogic = await PoolLogic.deploy();

    PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
    poolManagerLogic = await PoolManagerLogic.deploy();

    PoolFactory = await ethers.getContractFactory("PoolFactory");
    poolFactory = await upgrades.deployProxy(PoolFactory, [
      poolLogic.address,
      poolManagerLogic.address,
      ZERO_ADDRESS,
      dao.address,
    ]);
    await poolFactory.deployed();

    // Initialize Asset Price Consumer

    const SushiLPAggregator = await ethers.getContractFactory("SushiLPAggregator");
    sushiLpAggregator = await SushiLPAggregator.deploy(sushi_usdc_usdt, usdc_price_feed, usdt_price_feed);
    sushiLpAggregator.deployed();

    const assetWeth = { asset: weth, assetType: 0, aggregator: eth_price_feed };
    const assetUsdt = { asset: usdt, assetType: 0, aggregator: usdt_price_feed };
    const assetUsdc = { asset: usdc, assetType: 0, aggregator: usdc_price_feed };
    const assetSushiUsdcUsdt = { asset: sushi_usdc_usdt, assetType: 0, aggregator: sushiLpAggregator.address };
    const assetHandlerInitAssets = [assetWeth, assetUsdt, assetUsdc, assetSushiUsdcUsdt];

    assetHandler = await upgrades.deployProxy(AssetHandlerLogic, [poolFactory.address, assetHandlerInitAssets]);
    await assetHandler.deployed();
    await poolFactory.setAssetHandler(assetHandler.address);
    await assetHandler.setChainlinkTimeout((3600 * 24 * 365).toString()); // 1 year expiry

    const ERC20Guard = await ethers.getContractFactory("ERC20Guard");
    erc20Guard = await ERC20Guard.deploy();
    erc20Guard.deployed();

    const UniswapV2RouterGuard = await ethers.getContractFactory("UniswapV2RouterGuard");
    uniswapV2RouterGuard = await UniswapV2RouterGuard.deploy(uniswapV2Factory);
    uniswapV2RouterGuard.deployed();

    sushiswapGuard = await UniswapV2RouterGuard.deploy(sushiswapFactory);
    sushiswapGuard.deployed();

    await poolFactory.connect(dao).setAssetGuard(0, erc20Guard.address);
    await poolFactory.connect(dao).setContractGuard(uniswapV2Router, uniswapV2RouterGuard.address);
    await poolFactory.connect(dao).setContractGuard(sushiswapRouter, sushiswapGuard.address);
  });

  it("Should be able to get WETH", async function () {
    const IWETH = await hre.artifacts.readArtifact("IWETH");
    WETH = await ethers.getContractAt(IWETH.abi, weth);
    const IERC20 = await hre.artifacts.readArtifact("IERC20");
    USDT = await ethers.getContractAt(IERC20.abi, usdt);
    USDC = await ethers.getContractAt(IERC20.abi, usdc);
    SushiUsdcUsdt = await ethers.getContractAt(IERC20.abi, sushi_usdc_usdt);
    const IUniswapV2Router = await hre.artifacts.readArtifact("IUniswapV2Router");
    UniswapRouter = await ethers.getContractAt(IUniswapV2Router.abi, uniswapV2Router);
    // deposit ETH -> WETH
    await WETH.deposit({ value: (5e18).toString() });
    // WETH -> USDT
    await WETH.approve(uniswapV2Router, (5e18).toString());
    await UniswapRouter.swapExactTokensForTokens(
      (5e18).toString(),
      0,
      [weth, usdc],
      logicOwner.address,
      Math.floor(Date.now() / 1000 + 100000000),
    );
  });

  it("Should be able to get lp price", async function () {
    const priceBefore = await assetHandler.getUSDPrice(sushi_usdc_usdt);

    const IUniswapV2Router = await hre.artifacts.readArtifact("IUniswapV2Router");
    SushiswapRouter = await ethers.getContractAt(IUniswapV2Router.abi, sushiswapRouter);
    // deposit ETH -> WETH
    await WETH.deposit({ value: (5e18).toString() });
    // WETH -> USDT
    await WETH.approve(sushiswapRouter, (5e18).toString());
    await SushiswapRouter.swapExactTokensForTokens(
      (5e18).toString(),
      0,
      [weth, usdc, usdt],
      logicOwner.address,
      Math.floor(Date.now() / 1000 + 100000000),
    );

    const priceAfter = await assetHandler.getUSDPrice(sushi_usdc_usdt);

    // console.log(priceBefore.toString(), priceAfter.toString())
    expect(priceBefore).to.be.lt(priceAfter);
  });

  it("Should be able to createFund", async function () {
    await poolLogic.initialize(poolFactory.address, false, "Test Fund", "DHTF");

    console.log("Passed poolLogic Init!");

    await poolManagerLogic.initialize(poolFactory.address, manager.address, "Barren Wuffet", poolLogic.address, [
      [usdc, true],
      [weth, true],
    ]);

    console.log("Passed poolManagerLogic Init!");

    let fundCreatedEvent = new Promise((resolve, reject) => {
      poolFactory.on(
        "FundCreated",
        (
          fundAddress,
          isPoolPrivate,
          fundName,
          managerName,
          manager,
          time,
          managerFeeNumerator,
          managerFeeDenominator,
          event,
        ) => {
          event.removeListener();

          resolve({
            fundAddress: fundAddress,
            isPoolPrivate: isPoolPrivate,
            fundName: fundName,
            // fundSymbol: fundSymbol,
            managerName: managerName,
            manager: manager,
            time: time,
            managerFeeNumerator: managerFeeNumerator,
            managerFeeDenominator: managerFeeDenominator,
          });
        },
      );

      setTimeout(() => {
        reject(new Error("timeout"));
      }, 60000);
    });

    await expect(
      poolFactory.createFund(
        false,
        manager.address,
        "Barren Wuffet",
        "Test Fund",
        "DHTF",
        new ethers.BigNumber.from("6000"),
        [
          [usdc, true],
          [weth, true],
        ],
      ),
    ).to.be.revertedWith("invalid fraction");

    await poolFactory.createFund(
      false,
      manager.address,
      "Barren Wuffet",
      "Test Fund",
      "DHTF",
      new ethers.BigNumber.from("5000"),
      [
        [usdc, true],
        [weth, true],
      ],
    );

    let event = await fundCreatedEvent;

    fundAddress = event.fundAddress;
    expect(event.isPoolPrivate).to.be.false;
    expect(event.fundName).to.equal("Test Fund");
    // expect(event.fundSymbol).to.equal("DHTF");
    expect(event.managerName).to.equal("Barren Wuffet");
    expect(event.manager).to.equal(manager.address);
    expect(event.managerFeeNumerator.toString()).to.equal("5000");
    expect(event.managerFeeDenominator.toString()).to.equal("10000");

    let deployedFunds = await poolFactory.getDeployedFunds();
    let deployedFundsLength = deployedFunds.length;
    expect(deployedFundsLength.toString()).to.equal("1");

    let isPool = await poolFactory.isPool(fundAddress);
    expect(isPool).to.be.true;

    let poolManagerLogicAddress = await poolFactory.getLogic(1);
    expect(poolManagerLogicAddress).to.equal(poolManagerLogic.address);

    let poolLogicAddress = await poolFactory.getLogic(2);
    expect(poolLogicAddress).to.equal(poolLogic.address);

    poolLogicProxy = await PoolLogic.attach(fundAddress);
    let poolManagerLogicProxyAddress = await poolLogicProxy.poolManagerLogic();
    poolManagerLogicProxy = await PoolManagerLogic.attach(poolManagerLogicProxyAddress);

    //default assets are supported
    let supportedAssets = await poolManagerLogicProxy.getSupportedAssets();
    let numberOfSupportedAssets = supportedAssets.length;
    expect(numberOfSupportedAssets).to.eq(2);
    expect(await poolManagerLogicProxy.isSupportedAsset(usdc)).to.be.true;
    expect(await poolManagerLogicProxy.isSupportedAsset(weth)).to.be.true;

    //Other assets are not supported
    expect(await poolManagerLogicProxy.isSupportedAsset(usdt)).to.be.false;
  });

  it("should be able to deposit", async function () {
    let depositEvent = new Promise((resolve, reject) => {
      poolLogicProxy.on(
        "Deposit",
        (
          fundAddress,
          investor,
          assetDeposited,
          valueDeposited,
          fundTokensReceived,
          totalInvestorFundTokens,
          fundValue,
          totalSupply,
          time,
          event,
        ) => {
          event.removeListener();

          resolve({
            fundAddress: fundAddress,
            investor: investor,
            assetDeposited: assetDeposited,
            valueDeposited: valueDeposited,
            fundTokensReceived: fundTokensReceived,
            totalInvestorFundTokens: totalInvestorFundTokens,
            fundValue: fundValue,
            totalSupply: totalSupply,
            time: time,
          });
        },
      );

      setTimeout(() => {
        reject(new Error("timeout"));
      }, 60000);
    });

    let totalFundValue = await poolManagerLogicProxy.totalFundValue();
    expect(totalFundValue.toString()).to.equal("0");

    await expect(poolLogicProxy.deposit(usdt, (100e6).toString())).to.be.revertedWith("invalid deposit asset");

    await USDC.approve(poolLogicProxy.address, (100e6).toString());
    await poolLogicProxy.deposit(usdc, (100e6).toString());
    let event = await depositEvent;

    expect(event.fundAddress).to.equal(poolLogicProxy.address);
    expect(event.investor).to.equal(logicOwner.address);
    checkAlmostSame(event.valueDeposited, (100e18).toString());
    checkAlmostSame(event.fundTokensReceived, (100e18).toString());
    checkAlmostSame(event.totalInvestorFundTokens, (100e18).toString());
    checkAlmostSame(event.fundValue, (100e18).toString());
    checkAlmostSame(event.totalSupply, (100e18).toString());
  });

  it("Should be able to approve", async () => {
    const IERC20 = await hre.artifacts.readArtifact("IERC20");
    const iERC20 = new ethers.utils.Interface(IERC20.abi);
    let approveABI = iERC20.encodeFunctionData("approve", [usdc, (100e6).toString()]);
    await expect(poolLogicProxy.connect(manager).execTransaction(usdt, approveABI)).to.be.revertedWith(
      "asset not enabled in pool",
    );

    await expect(poolLogicProxy.connect(manager).execTransaction(usdc, approveABI)).to.be.revertedWith(
      "unsupported spender approval",
    );

    approveABI = iERC20.encodeFunctionData("approve", [uniswapV2Router, (100e6).toString()]);
    await poolLogicProxy.connect(manager).execTransaction(usdc, approveABI);
  });

  it("should be able to swap tokens on uniswap.", async () => {
    let exchangeEvent = new Promise((resolve, reject) => {
      uniswapV2RouterGuard.on(
        "Exchange",
        (managerLogicAddress, sourceAsset, sourceAmount, destinationAsset, time, event) => {
          event.removeListener();

          resolve({
            managerLogicAddress: managerLogicAddress,
            sourceAsset: sourceAsset,
            sourceAmount: sourceAmount,
            destinationAsset: destinationAsset,
            time: time,
          });
        },
      );

      setTimeout(() => {
        reject(new Error("timeout"));
      }, 60000);
    });

    await poolManagerLogicProxy.connect(manager).changeAssets([[usdt, false]], [weth]);

    const sourceAmount = (50e6).toString();
    const IUniswapV2Router = await hre.artifacts.readArtifact("IUniswapV2Router");
    const iUniswapV2Router = new ethers.utils.Interface(IUniswapV2Router.abi);
    let swapABI = iUniswapV2Router.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      0,
      [usdc, weth],
      poolManagerLogicProxy.address,
      0,
    ]);

    await expect(
      poolLogicProxy.connect(manager).execTransaction("0x0000000000000000000000000000000000000000", swapABI),
    ).to.be.revertedWith("non-zero address is required");

    swapABI = iUniswapV2Router.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      0,
      [weth, usdt],
      poolLogicProxy.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(usdc, swapABI)).to.be.revertedWith(
      "invalid transaction",
    );

    swapABI = iUniswapV2Router.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      0,
      [weth, usdt],
      poolLogicProxy.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(uniswapV2Router, swapABI)).to.be.revertedWith(
      "unsupported source asset",
    );

    swapABI = iUniswapV2Router.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      0,
      [usdc, user.address, usdt],
      poolLogicProxy.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(uniswapV2Router, swapABI)).to.be.revertedWith(
      "invalid routing asset",
    );

    swapABI = iUniswapV2Router.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      0,
      [usdc, usdt, weth],
      poolLogicProxy.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(uniswapV2Router, swapABI)).to.be.revertedWith(
      "unsupported destination asset",
    );

    swapABI = iUniswapV2Router.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      0,
      [usdc, usdt],
      user.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(uniswapV2Router, swapABI)).to.be.revertedWith(
      "recipient is not pool",
    );

    swapABI = iUniswapV2Router.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      0,
      [usdc, usdt],
      poolLogicProxy.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(uniswapV2Router, swapABI)).to.be.revertedWith(
      "failed to execute the call",
    );

    swapABI = iUniswapV2Router.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      0,
      [usdc, usdt],
      poolLogicProxy.address,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);
    await poolLogicProxy.connect(manager).execTransaction(uniswapV2Router, swapABI);

    expect(await USDC.balanceOf(poolLogicProxy.address)).to.be.equal((50e6).toString());

    let event = await exchangeEvent;
    expect(event.sourceAsset).to.equal(usdc);
    expect(event.sourceAmount).to.equal((50e6).toString());
    expect(event.destinationAsset).to.equal(usdt);
  });

  it("should be able to add liquidity on sushiswap.", async () => {
    let addLiquidityEvent = new Promise((resolve, reject) => {
      sushiswapGuard.on("AddLiquidity", (managerLogicAddress, tokenA, tokenB, pair, time, event) => {
        event.removeListener();

        resolve({
          managerLogicAddress,
          tokenA,
          tokenB,
          pair,
          amountADesired,
          amountBDesired,
          time,
        });
      });

      setTimeout(() => {
        reject(new Error("timeout"));
      }, 60000);
    });

    const tokenA = usdc;
    const tokenB = usdt;
    const amountADesired = (25e6).toString();
    const amountBDesired = (25e6).toString();
    const IUniswapV2Router = await hre.artifacts.readArtifact("IUniswapV2Router");
    const iUniswapV2Router = new ethers.utils.Interface(IUniswapV2Router.abi);
    let addLiquidityAbi = iUniswapV2Router.encodeFunctionData("addLiquidity", [
      tokenA,
      tokenB,
      amountADesired,
      amountBDesired,
      0,
      0,
      poolLogicProxy.address,
      0,
    ]);

    await expect(
      poolLogicProxy.connect(manager).execTransaction("0x0000000000000000000000000000000000000000", addLiquidityAbi),
    ).to.be.revertedWith("non-zero address is required");

    await expect(poolLogicProxy.connect(manager).execTransaction(usdc, addLiquidityAbi)).to.be.revertedWith(
      "invalid transaction",
    );

    addLiquidityAbi = iUniswapV2Router.encodeFunctionData("addLiquidity", [
      weth,
      tokenB,
      amountADesired,
      amountBDesired,
      0,
      0,
      poolLogicProxy.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(sushiswapRouter, addLiquidityAbi)).to.be.revertedWith(
      "unsupported asset: tokenA",
    );

    addLiquidityAbi = iUniswapV2Router.encodeFunctionData("addLiquidity", [
      tokenA,
      weth,
      amountADesired,
      amountBDesired,
      0,
      0,
      poolLogicProxy.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(sushiswapRouter, addLiquidityAbi)).to.be.revertedWith(
      "unsupported asset: tokenB",
    );

    addLiquidityAbi = iUniswapV2Router.encodeFunctionData("addLiquidity", [
      tokenA,
      tokenB,
      amountADesired,
      amountBDesired,
      0,
      0,
      poolLogicProxy.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(sushiswapRouter, addLiquidityAbi)).to.be.revertedWith(
      "unsupported lp asset",
    );

    await poolManagerLogicProxy.connect(manager).changeAssets([[sushi_usdc_usdt, false]], []);

    addLiquidityAbi = iUniswapV2Router.encodeFunctionData("addLiquidity", [
      tokenA,
      tokenB,
      amountADesired,
      amountBDesired,
      0,
      0,
      user.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(sushiswapRouter, addLiquidityAbi)).to.be.revertedWith(
      "recipient is not pool",
    );

    addLiquidityAbi = iUniswapV2Router.encodeFunctionData("addLiquidity", [
      tokenA,
      tokenB,
      amountADesired,
      amountBDesired,
      0,
      0,
      poolLogicProxy.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(sushiswapRouter, addLiquidityAbi)).to.be.revertedWith(
      "failed to execute the call",
    );

    const IERC20 = await hre.artifacts.readArtifact("IERC20");
    const iERC20 = new ethers.utils.Interface(IERC20.abi);
    let approveABI = iERC20.encodeFunctionData("approve", [sushiswapRouter, amountADesired]);
    await poolLogicProxy.connect(manager).execTransaction(usdc, approveABI);
    approveABI = iERC20.encodeFunctionData("approve", [sushiswapRouter, amountBDesired]);
    await poolLogicProxy.connect(manager).execTransaction(usdt, approveABI);

    expect(await SushiUsdcUsdt.balanceOf(poolLogicProxy.address)).to.be.equal(0);

    addLiquidityAbi = iUniswapV2Router.encodeFunctionData("addLiquidity", [
      tokenA,
      tokenB,
      amountADesired,
      amountBDesired,
      0,
      0,
      poolLogicProxy.address,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);
    await poolLogicProxy.connect(manager).execTransaction(sushiswapRouter, addLiquidityAbi);

    expect(await SushiUsdcUsdt.balanceOf(poolLogicProxy.address)).to.be.gt(0);

    let event = await addLiquidityEvent;
    expect(event.tokenA).to.equal(usdc);
    expect(event.tokenB).to.equal(usdt);
    expect(event.pair).to.equal(sushi_usdc_usdt);
  });

  it("should be able to remove liquidity on sushiswap.", async () => {
    let removeLiquidityEvent = new Promise((resolve, reject) => {
      sushiswapGuard.on("RemoveLiquidity", (managerLogicAddress, tokenA, tokenB, pair, liquidity, time, event) => {
        event.removeListener();

        resolve({
          managerLogicAddress,
          tokenA,
          tokenB,
          pair,
          liquidity,
          time,
        });
      });

      setTimeout(() => {
        reject(new Error("timeout"));
      }, 60000);
    });

    const tokenA = usdc;
    const tokenB = usdt;
    const liquidity = await SushiUsdcUsdt.balanceOf(poolLogicProxy.address);
    const IUniswapV2Router = await hre.artifacts.readArtifact("IUniswapV2Router");
    const iUniswapV2Router = new ethers.utils.Interface(IUniswapV2Router.abi);
    let removeLiquidityAbi = iUniswapV2Router.encodeFunctionData("removeLiquidity", [
      tokenA,
      tokenB,
      liquidity,
      0,
      0,
      poolLogicProxy.address,
      0,
    ]);

    await expect(
      poolLogicProxy.connect(manager).execTransaction("0x0000000000000000000000000000000000000000", removeLiquidityAbi),
    ).to.be.revertedWith("non-zero address is required");

    await expect(poolLogicProxy.connect(manager).execTransaction(usdc, removeLiquidityAbi)).to.be.revertedWith(
      "invalid transaction",
    );

    removeLiquidityAbi = iUniswapV2Router.encodeFunctionData("removeLiquidity", [
      weth,
      tokenB,
      liquidity,
      0,
      0,
      poolLogicProxy.address,
      0,
    ]);
    await expect(
      poolLogicProxy.connect(manager).execTransaction(sushiswapRouter, removeLiquidityAbi),
    ).to.be.revertedWith("unsupported asset: tokenA");

    removeLiquidityAbi = iUniswapV2Router.encodeFunctionData("removeLiquidity", [
      tokenA,
      weth,
      liquidity,
      0,
      0,
      poolLogicProxy.address,
      0,
    ]);
    await expect(
      poolLogicProxy.connect(manager).execTransaction(sushiswapRouter, removeLiquidityAbi),
    ).to.be.revertedWith("unsupported asset: tokenB");

    // await poolManagerLogicProxy.connect(manager).changeAssets([], [[sushi_usdc_usdt, false]]);

    // removeLiquidityAbi = iUniswapV2Router.encodeFunctionData("removeLiquidity", [tokenA, tokenB, liquidity, 0, 0, poolLogicProxy.address, 0]);
    // await expect(poolLogicProxy.connect(manager).execTransaction(sushiswapRouter, removeLiquidityAbi)).to.be.revertedWith("unsupported lp asset");

    // await poolManagerLogicProxy.connect(manager).changeAssets([[sushi_usdc_usdt, false]], []);

    removeLiquidityAbi = iUniswapV2Router.encodeFunctionData("removeLiquidity", [
      tokenA,
      tokenB,
      liquidity,
      0,
      0,
      user.address,
      0,
    ]);
    await expect(
      poolLogicProxy.connect(manager).execTransaction(sushiswapRouter, removeLiquidityAbi),
    ).to.be.revertedWith("recipient is not pool");

    removeLiquidityAbi = iUniswapV2Router.encodeFunctionData("removeLiquidity", [
      tokenA,
      tokenB,
      liquidity,
      0,
      0,
      poolLogicProxy.address,
      0,
    ]);
    await expect(
      poolLogicProxy.connect(manager).execTransaction(sushiswapRouter, removeLiquidityAbi),
    ).to.be.revertedWith("failed to execute the call");

    const IERC20 = await hre.artifacts.readArtifact("IERC20");
    const iERC20 = new ethers.utils.Interface(IERC20.abi);
    let approveABI = iERC20.encodeFunctionData("approve", [sushiswapRouter, liquidity]);
    await poolLogicProxy.connect(manager).execTransaction(sushi_usdc_usdt, approveABI);

    expect(await SushiUsdcUsdt.balanceOf(poolLogicProxy.address)).to.be.gt(0);

    removeLiquidityAbi = iUniswapV2Router.encodeFunctionData("removeLiquidity", [
      tokenA,
      tokenB,
      liquidity,
      0,
      0,
      poolLogicProxy.address,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);
    await poolLogicProxy.connect(manager).execTransaction(sushiswapRouter, removeLiquidityAbi);

    expect(await SushiUsdcUsdt.balanceOf(poolLogicProxy.address)).to.be.equal(0);

    let event = await removeLiquidityEvent;
    expect(event.tokenA).to.equal(usdc);
    expect(event.tokenB).to.equal(usdt);
    expect(event.pair).to.equal(sushi_usdc_usdt);
    expect(event.liquidity).to.equal(liquidity);
    checkAlmostSame(await USDC.balanceOf(poolLogicProxy.address), (50e6).toString());
    console.log((await USDC.balanceOf(poolLogicProxy.address)).toString());
    console.log((await USDT.balanceOf(poolLogicProxy.address)).toString());
    console.log((await poolLogicProxy.balanceOf(logicOwner.address)).toString());
  });

  it("should be able to swap tokens back on uniswap.", async () => {
    let exchangeEvent = new Promise((resolve, reject) => {
      uniswapV2RouterGuard.on(
        "Exchange",
        (managerLogicAddress, sourceAsset, sourceAmount, destinationAsset, time, event) => {
          event.removeListener();

          resolve({
            managerLogicAddress: managerLogicAddress,
            sourceAsset: sourceAsset,
            sourceAmount: sourceAmount,
            destinationAsset: destinationAsset,
            time: time,
          });
        },
      );

      setTimeout(() => {
        reject(new Error("timeout"));
      }, 60000);
    });

    const IERC20 = await hre.artifacts.readArtifact("IERC20");
    const iERC20 = new ethers.utils.Interface(IERC20.abi);
    const approveABI = iERC20.encodeFunctionData("approve", [uniswapV2Router, (100e6).toString()]);
    await poolLogicProxy.connect(manager).execTransaction(usdt, approveABI);

    const sourceAmount = await USDT.balanceOf(poolLogicProxy.address);
    const IUniswapV2Router = await hre.artifacts.readArtifact("IUniswapV2Router");
    const iUniswapV2Router = new ethers.utils.Interface(IUniswapV2Router.abi);
    const swapABI = iUniswapV2Router.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      0,
      [usdt, usdc],
      poolLogicProxy.address,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);
    await poolLogicProxy.connect(manager).execTransaction(uniswapV2Router, swapABI);

    let event = await exchangeEvent;
    expect(event.sourceAsset).to.equal(usdt);
    expect(event.sourceAmount).to.equal(sourceAmount);
    expect(event.destinationAsset).to.equal(usdc);
  });

  it("should be able to withdraw", async function () {
    let withdrawalEvent = new Promise((resolve, reject) => {
      poolLogicProxy.on(
        "Withdrawal",
        (
          fundAddress,
          investor,
          valueWithdrawn,
          fundTokensWithdrawn,
          totalInvestorFundTokens,
          fundValue,
          totalSupply,
          time,
          event,
        ) => {
          event.removeListener();

          resolve({
            fundAddress: fundAddress,
            investor: investor,
            valueWithdrawn: valueWithdrawn,
            fundTokensWithdrawn: fundTokensWithdrawn,
            totalInvestorFundTokens: totalInvestorFundTokens,
            fundValue: fundValue,
            totalSupply: totalSupply,
            time: time,
          });
        },
      );

      setTimeout(() => {
        reject(new Error("timeout"));
      }, 60000);
    });

    // Withdraw 50%
    let withdrawAmount = 50e18;

    await expect(poolLogicProxy.withdraw(withdrawAmount.toString())).to.be.revertedWith("cooldown active");

    ethers.provider.send("evm_increaseTime", [3600 * 24]); // add 1 day

    await poolLogicProxy.withdraw(withdrawAmount.toString());

    let event = await withdrawalEvent;
    expect(event.fundAddress).to.equal(poolLogicProxy.address);
    expect(event.investor).to.equal(logicOwner.address);
    checkAlmostSame(event.valueWithdrawn, (50e18).toString());
    checkAlmostSame(event.fundTokensWithdrawn, (50e18).toString());
    checkAlmostSame(event.totalInvestorFundTokens, (50e18).toString());
    checkAlmostSame(event.fundValue, (50e18).toString());
    checkAlmostSame(event.totalSupply, (50e18).toString());
  });
});
