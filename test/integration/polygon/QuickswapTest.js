const { ethers, upgrades } = require("hardhat");
const { expect, use } = require("chai");
const chaiAlmost = require("chai-almost");
const { checkAlmostSame, toBytes32 } = require("../../TestHelpers");

use(chaiAlmost());

const units = (value) => ethers.utils.parseUnits(value.toString());

const quickswapFactory = "0x5757371414417b8C6CAad45bAeF941aBc7d3Ab32";
const quickswapRouter = "0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff";

// For mainnet
const wmatic = "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270";
const weth = "0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619";
const usdc = "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174";
const usdt = "0xc2132D05D31c914a87C6611C10748AEb04B58e8F";
const quick = "0x831753DD7087CaC61aB5644b308642cc1c33Dc13";
const dai = "0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063";
const matic_price_feed = "0xAB594600376Ec9fD91F8e885dADF0CE036862dE0";
const eth_price_feed = "0xF9680D99D6C9589e2a93a78A04A279e509205945";
const usdc_price_feed = "0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7";
const usdt_price_feed = "0x0A6513e40db6EB1b165753AD52E80663aeA50545";

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

const quickLpUsdcWeth = "0x853Ee4b2A13f8a742d64C8F088bE7bA2131f670d";

describe("Quickswap V2 Test", function () {
  let WMatic, WETH, USDC, USDT, QuickLPUSDCWETH;
  let quickLPAggregator;
  let logicOwner, manager, dao, user;
  let PoolFactory, PoolLogic, PoolManagerLogic;
  let poolFactory, poolLogic, poolManagerLogic, poolLogicProxy, poolManagerLogicProxy, fundAddress;

  before(async function () {
    [logicOwner, manager, dao, user] = await ethers.getSigners();

    const AssetHandlerLogic = await ethers.getContractFactory("AssetHandler");

    const Governance = await ethers.getContractFactory("Governance");
    let governance = await Governance.deploy();
    console.log("governance deployed to:", governance.address);

    PoolLogic = await ethers.getContractFactory("PoolLogic");
    poolLogic = await PoolLogic.deploy();

    PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
    poolManagerLogic = await PoolManagerLogic.deploy();

    // Initialize Asset Price Consumer
    const assetWeth = { asset: weth, assetType: 0, aggregator: eth_price_feed };
    const assetUsdt = { asset: usdt, assetType: 0, aggregator: usdt_price_feed };
    const assetUsdc = { asset: usdc, assetType: 0, aggregator: usdc_price_feed };
    const assetHandlerInitAssets = [assetWeth, assetUsdt, assetUsdc];

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

    // Deploy Quick LP Aggregator
    const UniV2LPAggregator = await ethers.getContractFactory("UniV2LPAggregator");
    quickLPAggregator = await UniV2LPAggregator.deploy(quickLpUsdcWeth, poolFactory.address);
    const assetQuickLPWethUsdc = { asset: quickLpUsdcWeth, assetType: 5, aggregator: quickLPAggregator.address };
    await assetHandler.addAssets([assetQuickLPWethUsdc]);

    const ERC20Guard = await ethers.getContractFactory("ERC20Guard");
    erc20Guard = await ERC20Guard.deploy();
    await erc20Guard.deployed();

    const OpenAssetGuard = await ethers.getContractFactory("OpenAssetGuard");
    openAssetGuard = await OpenAssetGuard.deploy([wmatic, quick]);
    await openAssetGuard.deployed();

    const UniswapV2RouterGuard = await ethers.getContractFactory("UniswapV2RouterGuard");
    uniswapV2RouterGuard = await UniswapV2RouterGuard.deploy(quickswapFactory);
    await uniswapV2RouterGuard.deployed();

    quickLPAssetGuard = await ERC20Guard.deploy();
    await quickLPAssetGuard.deployed();

    await governance.setAssetGuard(0, erc20Guard.address);
    await governance.setAssetGuard(5, quickLPAssetGuard.address);
    await governance.setContractGuard(quickswapRouter, uniswapV2RouterGuard.address);
    await governance.setAddresses([[toBytes32("openAssetGuard"), openAssetGuard.address]]);
  });

  it("Should be able to get USDC", async function () {
    const IWETH = await hre.artifacts.readArtifact("IWETH");
    WMatic = await ethers.getContractAt(IWETH.abi, wmatic);
    const IERC20 = await hre.artifacts.readArtifact("IERC20");
    USDT = await ethers.getContractAt(IERC20.abi, usdt);
    USDC = await ethers.getContractAt(IERC20.abi, usdc);
    WETH = await ethers.getContractAt(IERC20.abi, weth);
    WMATIC = await ethers.getContractAt(IERC20.abi, wmatic);
    QuickLPUSDCWETH = await ethers.getContractAt(IERC20.abi, quickLpUsdcWeth);
    let balance = await ethers.provider.getBalance(logicOwner.address);
    console.log("Matic balance: ", balance.toString());
    balance = await WMATIC.balanceOf(logicOwner.address);
    console.log("WMatic balance: ", balance.toString());
    const IUniswapV2Router = await hre.artifacts.readArtifact("IUniswapV2Router");
    const QuickSwapRouter = await ethers.getContractAt(IUniswapV2Router.abi, quickswapRouter);
    // deposit Matic -> WMatic
    await WMatic.deposit({ value: units(500) });
    balance = await WMATIC.balanceOf(logicOwner.address);
    console.log("WMatic balance: ", balance.toString());
    // WMatic -> USDC
    await WMatic.approve(quickswapRouter, units(500));
    await QuickSwapRouter.swapExactTokensForTokens(
      units(500),
      0,
      [wmatic, usdc],
      logicOwner.address,
      Math.floor(Date.now() / 1000 + 100000000),
    );
    balance = await USDC.balanceOf(logicOwner.address);
    console.log("USDC balance: ", balance.toString());
  });

  it("Should be able to createFund", async function () {
    await poolLogic.initialize(poolFactory.address, false, "Test Fund", "DHTF");

    console.log("Passed poolLogic Init!");

    await poolManagerLogic.initialize(
      poolFactory.address,
      manager.address,
      "Barren Wuffet",
      poolLogic.address,
      "1000",
      [
        [usdc, true],
        [weth, true],
      ],
    );

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
    ).to.be.revertedWith("invalid manager fee");

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
        [usdt, true],
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
    expect(numberOfSupportedAssets).to.eq(3);
    expect(await poolManagerLogicProxy.isSupportedAsset(usdc)).to.be.true;
    expect(await poolManagerLogicProxy.isSupportedAsset(weth)).to.be.true;
    expect(await poolManagerLogicProxy.isSupportedAsset(usdt)).to.be.true;

    //Other assets are not supported
    expect(await poolManagerLogicProxy.isSupportedAsset(wmatic)).to.be.false;
  });

  it("should be able to deposit", async function () {
    let depositEvent = new Promise((resolve, reject) => {
      poolLogicProxy.on(
        "Deposit",
        (
          fundAddress,
          investor,
          assetDeposited,
          amountDeposited,
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
            amountDeposited: amountDeposited,
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

    let supportedAssets = await poolManagerLogicProxy.getSupportedAssets();
    console.log("supportedAsset: ", supportedAssets);

    let chainlinkEth = await ethers.getContractAt("AggregatorV3Interface", eth_price_feed);
    let ethPrice = await chainlinkEth.latestRoundData();
    console.log("eth price: ", ethPrice[1].toString());
    console.log("updatedAt: ", ethPrice[3].toString());

    let chainlinkUsdc = await ethers.getContractAt("AggregatorV3Interface", usdc_price_feed);
    let usdcPrice = await chainlinkUsdc.latestRoundData();
    console.log("usdc price: ", usdcPrice[1].toString());
    console.log("updatedAt: ", usdcPrice[3].toString());

    // Revert on second time
    let assetBalance = await poolManagerLogicProxy.assetBalance(usdc);
    console.log("assetBalance: ", assetBalance.toString());

    // Revert on second time
    let assetValue = await poolManagerLogicProxy["assetValue(address)"](usdc);
    console.log("assetValue: ", assetValue.toString());

    // Revert on second time
    totalFundValue = await poolManagerLogicProxy.totalFundValue();
    expect(totalFundValue.toString()).to.equal("0");

    await expect(poolLogicProxy.deposit(wmatic, (200e6).toString())).to.be.revertedWith("invalid deposit asset");

    await USDC.approve(poolLogicProxy.address, (200e6).toString());
    await poolLogicProxy.deposit(usdc, (200e6).toString());
    let event = await depositEvent;

    expect(event.fundAddress).to.equal(poolLogicProxy.address);
    expect(event.investor).to.equal(logicOwner.address);
    checkAlmostSame(event.valueDeposited, units(200));
    checkAlmostSame(event.fundTokensReceived, units(200));
    checkAlmostSame(event.totalInvestorFundTokens, units(200));
    checkAlmostSame(event.fundValue, units(200));
    checkAlmostSame(event.totalSupply, units(200));
  });

  it("Should be able to approve", async () => {
    const IERC20 = await hre.artifacts.readArtifact("IERC20");
    const iERC20 = new ethers.utils.Interface(IERC20.abi);
    let approveABI = iERC20.encodeFunctionData("approve", [usdc, (200e6).toString()]);
    await expect(poolLogicProxy.connect(manager).execTransaction(wmatic, approveABI)).to.be.revertedWith(
      "asset not enabled in pool",
    );

    await expect(poolLogicProxy.connect(manager).execTransaction(usdc, approveABI)).to.be.revertedWith(
      "unsupported spender approval",
    );

    approveABI = iERC20.encodeFunctionData("approve", [quickswapRouter, (200e6).toString()]);
    await poolLogicProxy.connect(manager).execTransaction(usdc, approveABI);
  });

  it("should be able to swap tokens on quickswap(swapTokensForExactTokens).", async () => {
    let exchangeEvent = new Promise((resolve, reject) => {
      uniswapV2RouterGuard.on(
        "ExchangeTo",
        (managerLogicAddress, sourceAsset, destinationAsset, dstAmount, time, event) => {
          event.removeListener();

          resolve({
            managerLogicAddress: managerLogicAddress,
            sourceAsset: sourceAsset,
            destinationAsset: destinationAsset,
            dstAmount: dstAmount,
            time: time,
          });
        },
      );

      setTimeout(() => {
        reject(new Error("timeout"));
      }, 60000);
    });

    const dstAmount = (100e6).toString();
    const IUniswapV2Router = await hre.artifacts.readArtifact("IUniswapV2Router");
    const iQuickswapRouter = new ethers.utils.Interface(IUniswapV2Router.abi);
    let swapABI = iQuickswapRouter.encodeFunctionData("swapTokensForExactTokens", [
      dstAmount,
      0,
      [usdc, usdt],
      poolManagerLogicProxy.address,
      0,
    ]);

    await expect(
      poolLogicProxy.connect(manager).execTransaction("0x0000000000000000000000000000000000000000", swapABI),
    ).to.be.revertedWith("non-zero address is required");

    swapABI = iQuickswapRouter.encodeFunctionData("swapTokensForExactTokens", [
      dstAmount,
      0,
      [usdc, usdt],
      poolLogicProxy.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(usdc, swapABI)).to.be.revertedWith(
      "invalid transaction",
    );

    swapABI = iQuickswapRouter.encodeFunctionData("swapTokensForExactTokens", [
      dstAmount,
      0,
      [usdc, weth, wmatic],
      poolLogicProxy.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(quickswapRouter, swapABI)).to.be.revertedWith(
      "unsupported destination asset",
    );

    swapABI = iQuickswapRouter.encodeFunctionData("swapTokensForExactTokens", [
      dstAmount,
      0,
      [usdc, usdt],
      user.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(quickswapRouter, swapABI)).to.be.revertedWith(
      "recipient is not pool",
    );

    swapABI = iQuickswapRouter.encodeFunctionData("swapTokensForExactTokens", [
      dstAmount,
      ethers.constants.MaxUint256,
      [usdc, usdt],
      poolLogicProxy.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(quickswapRouter, swapABI)).to.be.revertedWith(
      "UniswapV2Router: EXPIRED",
    );

    swapABI = iQuickswapRouter.encodeFunctionData("swapTokensForExactTokens", [
      dstAmount,
      ethers.constants.MaxUint256,
      [usdc, usdt],
      poolLogicProxy.address,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);
    await poolLogicProxy.connect(manager).execTransaction(quickswapRouter, swapABI);

    checkAlmostSame(await USDC.balanceOf(poolLogicProxy.address), dstAmount);

    let event = await exchangeEvent;
    expect(event.sourceAsset).to.equal(usdc);
    expect(event.destinationAsset).to.equal(usdt);
    expect(event.dstAmount).to.equal(dstAmount);
  });

  it("should be able to swap tokens on quickswap(swapExactTokensForTokens).", async () => {
    let exchangeEvent = new Promise((resolve, reject) => {
      uniswapV2RouterGuard.on(
        "ExchangeFrom",
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

    const sourceAmount = ethers.BigNumber.from(await USDC.balanceOf(poolLogicProxy.address)).div(2);
    const IUniswapV2Router = await hre.artifacts.readArtifact("IUniswapV2Router");
    const iQuickswapRouter = new ethers.utils.Interface(IUniswapV2Router.abi);
    let swapABI = iQuickswapRouter.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      0,
      [usdc, weth],
      poolManagerLogicProxy.address,
      0,
    ]);

    await expect(
      poolLogicProxy.connect(manager).execTransaction("0x0000000000000000000000000000000000000000", swapABI),
    ).to.be.revertedWith("non-zero address is required");

    swapABI = iQuickswapRouter.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      0,
      [wmatic, weth],
      poolLogicProxy.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(usdc, swapABI)).to.be.revertedWith(
      "invalid transaction",
    );

    swapABI = iQuickswapRouter.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      0,
      [usdc, weth, usdt],
      poolLogicProxy.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(quickswapRouter, swapABI)).to.be.revertedWith(
      "unsupported destination asset",
    );

    swapABI = iQuickswapRouter.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      0,
      [usdc, weth],
      user.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(quickswapRouter, swapABI)).to.be.revertedWith(
      "recipient is not pool",
    );

    swapABI = iQuickswapRouter.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      0,
      [usdc, weth],
      poolLogicProxy.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(quickswapRouter, swapABI)).to.be.revertedWith(
      "UniswapV2Router: EXPIRED",
    );

    swapABI = iQuickswapRouter.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      0,
      [usdc, weth],
      poolLogicProxy.address,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);
    await poolLogicProxy.connect(manager).execTransaction(quickswapRouter, swapABI);

    checkAlmostSame(await USDC.balanceOf(poolLogicProxy.address), sourceAmount);

    let event = await exchangeEvent;
    expect(event.sourceAsset).to.equal(usdc);
    expect(event.sourceAmount).to.equal(sourceAmount);
    expect(event.destinationAsset).to.equal(weth);
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
          withdrawnAssets,
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
            withdrawnAssets: withdrawnAssets,
            time: time,
          });
        },
      );

      setTimeout(() => {
        reject(new Error("timeout"));
      }, 60000);
    });

    // Withdraw 50%
    let withdrawAmount = units(100);

    await expect(poolLogicProxy.withdraw(withdrawAmount)).to.be.revertedWith("cooldown active");

    await poolFactory.setExitCooldown(0);

    await poolLogicProxy.withdraw(withdrawAmount);

    let event = await withdrawalEvent;
    expect(event.fundAddress).to.equal(poolLogicProxy.address);
    expect(event.investor).to.equal(logicOwner.address);
    checkAlmostSame(event.valueWithdrawn, units(100));
    checkAlmostSame(event.fundTokensWithdrawn, units(100));
    checkAlmostSame(event.totalInvestorFundTokens, units(100));
    checkAlmostSame(event.fundValue, units(100));
    checkAlmostSame(event.totalSupply, units(100));
  });

  it("manager can add liquidity", async () => {
    await poolManagerLogicProxy.connect(manager).changeAssets([[quickLpUsdcWeth, false]], []);

    const tokenA = usdc;
    const tokenB = weth;
    const amountADesired = await USDC.balanceOf(poolLogicProxy.address);
    const amountBDesired = await WETH.balanceOf(poolLogicProxy.address);
    const IUniswapV2Router = await hre.artifacts.readArtifact("IUniswapV2Router");
    const iUniswapV2Router = new ethers.utils.Interface(IUniswapV2Router.abi);
    const addLiquidityAbi = iUniswapV2Router.encodeFunctionData("addLiquidity", [
      tokenA,
      tokenB,
      amountADesired,
      amountBDesired,
      0,
      0,
      poolLogicProxy.address,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);

    const IERC20 = await hre.artifacts.readArtifact("IERC20");
    const iERC20 = new ethers.utils.Interface(IERC20.abi);
    let approveABI = iERC20.encodeFunctionData("approve", [quickswapRouter, amountADesired]);
    await poolLogicProxy.connect(manager).execTransaction(usdc, approveABI);
    approveABI = iERC20.encodeFunctionData("approve", [quickswapRouter, amountBDesired]);
    await poolLogicProxy.connect(manager).execTransaction(weth, approveABI);

    const lpBalanceBefore = await QuickLPUSDCWETH.balanceOf(poolLogicProxy.address);
    const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
    const wethBalanceBefore = await WETH.balanceOf(poolLogicProxy.address);
    const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

    expect(lpBalanceBefore).to.be.equal(0);

    await poolLogicProxy.connect(manager).execTransaction(quickswapRouter, addLiquidityAbi);

    expect(await QuickLPUSDCWETH.balanceOf(poolLogicProxy.address)).to.be.gt(lpBalanceBefore);
    expect(await USDC.balanceOf(poolLogicProxy.address)).to.be.lt(usdcBalanceBefore);
    expect(await WETH.balanceOf(poolLogicProxy.address)).to.be.lt(wethBalanceBefore);
    checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
  });

  it("should be able to remove liquidity on quickswap.", async () => {
    const tokenA = usdc;
    const tokenB = weth;
    const liquidity = await QuickLPUSDCWETH.balanceOf(poolLogicProxy.address);
    const IUniswapV2Router = await hre.artifacts.readArtifact("IUniswapV2Router");
    const iUniswapV2Router = new ethers.utils.Interface(IUniswapV2Router.abi);

    let removeLiquidityAbi = iUniswapV2Router.encodeFunctionData("removeLiquidity", [
      wmatic,
      tokenB,
      liquidity,
      0,
      0,
      poolLogicProxy.address,
      0,
    ]);
    await expect(
      poolLogicProxy.connect(manager).execTransaction(quickswapRouter, removeLiquidityAbi),
    ).to.be.revertedWith("unsupported asset: tokenA");

    removeLiquidityAbi = iUniswapV2Router.encodeFunctionData("removeLiquidity", [
      tokenA,
      wmatic,
      liquidity,
      0,
      0,
      poolLogicProxy.address,
      0,
    ]);
    await expect(
      poolLogicProxy.connect(manager).execTransaction(quickswapRouter, removeLiquidityAbi),
    ).to.be.revertedWith("unsupported asset: tokenB");

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
      poolLogicProxy.connect(manager).execTransaction(quickswapRouter, removeLiquidityAbi),
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
      poolLogicProxy.connect(manager).execTransaction(quickswapRouter, removeLiquidityAbi),
    ).to.be.revertedWith("UniswapV2Router: EXPIRED");

    const IERC20 = await hre.artifacts.readArtifact("IERC20");
    const iERC20 = new ethers.utils.Interface(IERC20.abi);
    let approveABI = iERC20.encodeFunctionData("approve", [quickswapRouter, liquidity]);
    await poolLogicProxy.connect(manager).execTransaction(quickLpUsdcWeth, approveABI);

    removeLiquidityAbi = iUniswapV2Router.encodeFunctionData("removeLiquidity", [
      tokenA,
      tokenB,
      liquidity,
      0,
      0,
      poolLogicProxy.address,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);

    const lpBalanceBefore = await QuickLPUSDCWETH.balanceOf(poolLogicProxy.address);
    const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
    const wethBalanceBefore = await WETH.balanceOf(poolLogicProxy.address);
    const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

    expect(lpBalanceBefore).to.gt(0);

    await poolLogicProxy.connect(manager).execTransaction(quickswapRouter, removeLiquidityAbi);

    expect(await QuickLPUSDCWETH.balanceOf(poolLogicProxy.address)).to.be.equal(0);
    expect(await USDC.balanceOf(poolLogicProxy.address)).to.be.gt(usdcBalanceBefore);
    expect(await WETH.balanceOf(poolLogicProxy.address)).to.be.gt(wethBalanceBefore);
    checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
  });

  it("Should be able to approve non-supported asset", async () => {
    // transfer wmatic for testing
    const depositAmount = units(500);
    await WMatic.deposit({ value: depositAmount });
    await WMatic.transfer(poolLogicProxy.address, depositAmount);

    const IERC20 = await hre.artifacts.readArtifact("IERC20");
    const iERC20 = new ethers.utils.Interface(IERC20.abi);
    let approveABI = iERC20.encodeFunctionData("approve", [dai, depositAmount]);

    await expect(poolLogicProxy.connect(manager).execTransaction(dai, approveABI)).to.be.revertedWith("invalid asset");

    await expect(poolLogicProxy.connect(manager).execTransaction(wmatic, approveABI)).to.be.revertedWith(
      "unsupported spender approval",
    );

    approveABI = iERC20.encodeFunctionData("approve", [quickswapRouter, depositAmount]);
    await poolLogicProxy.connect(manager).execTransaction(wmatic, approveABI);
  });

  it("Should be able to swap non-supported asset", async () => {
    const sourceAmount = units(100);
    const IUniswapV2Router = await hre.artifacts.readArtifact("IUniswapV2Router");
    const iQuickswapRouter = new ethers.utils.Interface(IUniswapV2Router.abi);
    let swapABI = iQuickswapRouter.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      0,
      [wmatic, weth],
      poolLogicProxy.address,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);

    const wethBalanceBefore = await WETH.balanceOf(poolLogicProxy.address);

    await poolLogicProxy.connect(manager).execTransaction(quickswapRouter, swapABI);

    const wethBalanceAfter = await WETH.balanceOf(poolLogicProxy.address);
    expect(wethBalanceAfter).gt(wethBalanceBefore);
  });

  it("Should be able to swap non-supported asset (routing)", async () => {
    const sourceAmount = units(100);
    const IUniswapV2Router = await hre.artifacts.readArtifact("IUniswapV2Router");
    const iQuickswapRouter = new ethers.utils.Interface(IUniswapV2Router.abi);
    let swapABI = iQuickswapRouter.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      0,
      [wmatic, quick, weth],
      poolLogicProxy.address,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);

    const wethBalanceBefore = await WETH.balanceOf(poolLogicProxy.address);

    await poolLogicProxy.connect(manager).execTransaction(quickswapRouter, swapABI);

    const wethBalanceAfter = await WETH.balanceOf(poolLogicProxy.address);
    expect(wethBalanceAfter).gt(wethBalanceBefore);
  });
});
