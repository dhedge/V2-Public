const { ethers, upgrades } = require("hardhat");
const { expect, use } = require("chai");
const chaiAlmost = require("chai-almost");
const { checkAlmostSame, getAmountOut } = require("../../TestHelpers");

use(chaiAlmost());

const oneInchV3Router = "0x11111112542D85B3EF69AE05771c2dCCff4fAa26";
const uniswapV2Factory = "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f";
const uniswapV2Router = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";
const sushiswapRouter = "0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F";
const sushiswapFactory = "0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac";

// For mainnet
const weth = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
const usdc = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
const usdt = "0xdAC17F958D2ee523a2206206994597C13D831ec7";
const eth_price_feed = "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419";
const usdt_price_feed = "0x3E7d1eAB13ad0104d2750B8863b489D65364e32D";
const usdc_price_feed = "0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6";
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

const sushiLpUsdcUsdt = "0xD86A120a06255Df8D4e2248aB04d4267E23aDfaA";
const sushiLpDaiUsdt = "0x055CEDfe14BCE33F985C41d9A1934B7654611AAC";

describe("OneInch V3 Test", function () {
  let WETH, USDC, USDT, UniswapRouter;
  let logicOwner, manager, dao, user;
  let PoolFactory, PoolLogic, PoolManagerLogic, assetHandler;
  let poolFactory, poolLogic, poolManagerLogic, poolLogicProxy, poolManagerLogicProxy, fundAddress;
  let uniswapV2RouterGuard;

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

    const ERC20Guard = await ethers.getContractFactory("ERC20Guard");
    erc20Guard = await ERC20Guard.deploy();
    erc20Guard.deployed();

    const UniswapV2RouterGuard = await ethers.getContractFactory("UniswapV2RouterGuard");
    uniswapV2RouterGuard = await UniswapV2RouterGuard.deploy(2, 100); // set slippage 2% for testing
    uniswapV2RouterGuard.deployed();

    const OneInchV3Guard = await ethers.getContractFactory("OneInchV3Guard");
    oneInchV3Guard = await OneInchV3Guard.deploy(2, 100); // set slippage 2%
    oneInchV3Guard.deployed();

    await governance.setAssetGuard(0, erc20Guard.address);
    await governance.setAssetGuard(2, erc20Guard.address); // as normal erc20 token
    await governance.setContractGuard(uniswapV2Router, uniswapV2RouterGuard.address);
    await governance.setContractGuard(sushiswapRouter, uniswapV2RouterGuard.address);
    await governance.setContractGuard(oneInchV3Router, oneInchV3Guard.address);
  });

  it("Should be able to get USDC", async function () {
    const IWETH = await hre.artifacts.readArtifact("IWETH");
    WETH = await ethers.getContractAt(IWETH.abi, weth);
    const IERC20 = await hre.artifacts.readArtifact("IERC20");
    USDT = await ethers.getContractAt(IERC20.abi, usdt);
    USDC = await ethers.getContractAt(IERC20.abi, usdc);
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

    approveABI = iERC20.encodeFunctionData("approve", [oneInchV3Router, (100e6).toString()]);
    await poolLogicProxy.connect(manager).execTransaction(usdc, approveABI);
  });

  it("should be able to swap tokens on oneInch - unoswap.", async () => {
    const srcAsset = usdc;
    const srcAmount = (10e6).toString();
    const IAggregationRouterV3 = await hre.artifacts.readArtifact("IAggregationRouterV3");
    const iAggregationRouterV3 = new ethers.utils.Interface(IAggregationRouterV3.abi);

    let unoswapABI = iAggregationRouterV3.encodeFunctionData("unoswap", [
      srcAsset,
      srcAmount,
      ethers.BigNumber.from(await getAmountOut(sushiswapRouter, srcAmount, [usdc, usdt]))
        .mul(95)
        .div(100),
      // 0xD86A120a06255Df8D4e2248aB04d4267E23aDfaA
      ["0x80000000000000003b6d0340" + sushiLpDaiUsdt.slice(2, sushiLpDaiUsdt.length)],
    ]);

    await expect(poolLogicProxy.connect(manager).execTransaction(oneInchV3Router, unoswapABI)).to.be.revertedWith(
      "invalid path",
    );

    console.log(
      ethers.BigNumber.from(await getAmountOut(sushiswapRouter, srcAmount, [usdc, usdt]))
        .mul(95)
        .div(100)
        .toString(),
    );
    unoswapABI = iAggregationRouterV3.encodeFunctionData("unoswap", [
      srcAsset,
      srcAmount,
      ethers.BigNumber.from(await getAmountOut(sushiswapRouter, srcAmount, [usdc, usdt]))
        .mul(95)
        .div(100),
      // 0xD86A120a06255Df8D4e2248aB04d4267E23aDfaA
      ["0x80000000000000003b6d0340" + sushiLpUsdcUsdt.slice(2, sushiLpUsdcUsdt.length)],
    ]);

    await expect(poolLogicProxy.connect(manager).execTransaction(oneInchV3Router, unoswapABI)).to.be.revertedWith(
      "unsupported destination asset",
    );

    await poolManagerLogicProxy.connect(manager).changeAssets([[usdt, false]], []);

    await expect(poolLogicProxy.connect(manager).execTransaction(oneInchV3Router, unoswapABI)).to.be.revertedWith(
      "slippage limit exceed",
    );

    await oneInchV3Guard.setSlippageLimit(10, 100); // 10%

    const usdtBalanceBefore = ethers.BigNumber.from(await USDT.balanceOf(poolLogicProxy.address));
    const usdcBalanceBefore = ethers.BigNumber.from(await USDC.balanceOf(poolLogicProxy.address));

    await poolLogicProxy.connect(manager).execTransaction(oneInchV3Router, unoswapABI);

    const usdtBalanceAfter = await USDT.balanceOf(poolLogicProxy.address);
    const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
    console.log(usdcBalanceAfter.toString(), usdcBalanceBefore.toString());
    // checkAlmostSame(usdcBalanceAfter, usdcBalanceBefore.sub(srcAmount));
    console.log(usdtBalanceAfter.toString(), usdtBalanceBefore.toString());
    // checkAlmostSame(usdtBalanceAfter, usdtBalanceBefore.add(srcAmount));
  });
});
