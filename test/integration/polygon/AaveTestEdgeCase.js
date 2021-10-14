const { ethers, upgrades } = require("hardhat");
const { expect, use } = require("chai");
const chaiAlmost = require("chai-almost");
const { checkAlmostSame, approxEq, toBytes32, getAmountOut, units } = require("../../TestHelpers");
const { sushi, aave, assets, price_feeds } = require("../polygon-data");

use(chaiAlmost());

describe("Polygon Mainnet Test", function () {
  let WMatic, WETH, USDC, USDT, AMUSDC, AMWETH, VariableUSDT, VariableWETH;
  let sushiLPAggregator, usdPriceAggregator, sushiMiniChefV2Guard;
  let logicOwner, manager, dao, user;
  let PoolFactory, PoolLogic, PoolManagerLogic;
  let poolFactory, poolLogic, poolManagerLogic, poolLogicProxy, poolManagerLogicProxy, fundAddress;
  let IERC20, iERC20, ILendingPool, iLendingPool, IUniswapV2Router, iSushiswapV2Router;

  before(async function () {
    [logicOwner, manager, dao, user] = await ethers.getSigners();

    IERC20 = await hre.artifacts.readArtifact("IERC20");
    iERC20 = new ethers.utils.Interface(IERC20.abi);

    ILendingPool = await hre.artifacts.readArtifact("ILendingPool");
    iLendingPool = new ethers.utils.Interface(ILendingPool.abi);

    IUniswapV2Router = await hre.artifacts.readArtifact("IUniswapV2Router");
    iSushiswapV2Router = new ethers.utils.Interface(IUniswapV2Router.abi);

    const AssetHandlerLogic = await ethers.getContractFactory("AssetHandler");

    const Governance = await ethers.getContractFactory("Governance");
    let governance = await Governance.deploy();
    console.log("governance deployed to:", governance.address);

    const PoolPerformance = await ethers.getContractFactory("PoolPerformance");
    const poolPerformance = await upgrades.deployProxy(PoolPerformance, [aave.protocolDataProvider]);
    await poolPerformance.deployed();

    PoolLogic = await ethers.getContractFactory("PoolLogic");
    poolLogic = await PoolLogic.deploy();

    PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
    poolManagerLogic = await PoolManagerLogic.deploy();

    // Deploy USD Price Aggregator
    const USDPriceAggregator = await ethers.getContractFactory("USDPriceAggregator");
    usdPriceAggregator = await USDPriceAggregator.deploy();
    // Initialize Asset Price Consumer
    const assetWmatic = { asset: assets.wmatic, assetType: 0, aggregator: price_feeds.matic };
    const assetWeth = { asset: assets.weth, assetType: 0, aggregator: price_feeds.eth };
    const assetUsdt = { asset: assets.usdt, assetType: 0, aggregator: price_feeds.usdt };
    const assetSushi = { asset: assets.sushi, assetType: 0, aggregator: price_feeds.sushi };
    const assetLendingPool = { asset: aave.lendingPool, assetType: 3, aggregator: usdPriceAggregator.address };
    const assetDai = { asset: assets.dai, assetType: 4, aggregator: price_feeds.dai }; // Lending enabled
    const assetUsdc = { asset: assets.usdc, assetType: 4, aggregator: price_feeds.usdc }; // Lending enabled
    const assetHandlerInitAssets = [
      assetWmatic,
      assetWeth,
      assetUsdt,
      assetDai,
      assetUsdc,
      assetSushi,
      assetLendingPool,
    ];

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

    // Deploy Sushi LP Aggregator
    const UniV2LPAggregator = await ethers.getContractFactory("UniV2LPAggregator");
    sushiLPAggregator = await UniV2LPAggregator.deploy(sushi.pools.usdc_weth.address, poolFactory.address);
    const assetSushiLPWethUsdc = {
      asset: sushi.pools.usdc_weth.address,
      assetType: 2,
      aggregator: sushiLPAggregator.address,
    };
    await assetHandler.addAssets([assetSushiLPWethUsdc]);

    const ERC20Guard = await ethers.getContractFactory("ERC20Guard");
    erc20Guard = await ERC20Guard.deploy();
    erc20Guard.deployed();

    const OpenAssetGuard = await ethers.getContractFactory("OpenAssetGuard");
    openAssetGuard = await OpenAssetGuard.deploy([]);
    await openAssetGuard.deployed();

    const UniswapV2RouterGuard = await ethers.getContractFactory("UniswapV2RouterGuard");
    uniswapV2RouterGuard = await UniswapV2RouterGuard.deploy(2, 100); // set slippage 2% for testing
    uniswapV2RouterGuard.deployed();

    const SushiMiniChefV2Guard = await ethers.getContractFactory("SushiMiniChefV2Guard");
    sushiMiniChefV2Guard = await SushiMiniChefV2Guard.deploy(assets.sushi, assets.wmatic);
    sushiMiniChefV2Guard.deployed();

    const SushiLPAssetGuard = await ethers.getContractFactory("SushiLPAssetGuard");
    sushiLPAssetGuard = await SushiLPAssetGuard.deploy(sushi.minichef); // initialise with Sushi staking pool Id
    sushiLPAssetGuard.deployed();

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
      [toBytes32("swapRouter"), sushi.router],
      [toBytes32("aaveProtocolDataProvider"), aave.protocolDataProvider],
      [toBytes32("weth"), assets.weth],
      [toBytes32("openAssetGuard"), openAssetGuard.address],
    ]);

    await poolFactory.setExitFee(5, 1000); // 0.5%
  });

  it("Should be able to get USDC", async function () {
    const IWETH = await hre.artifacts.readArtifact("IWETH");
    WMatic = await ethers.getContractAt(IWETH.abi, assets.wmatic);
    USDT = await ethers.getContractAt(IERC20.abi, assets.usdt);
    DAI = await ethers.getContractAt(IERC20.abi, assets.dai);
    USDC = await ethers.getContractAt(IERC20.abi, assets.usdc);
    WETH = await ethers.getContractAt(IERC20.abi, assets.weth);
    WMATIC = await ethers.getContractAt(IERC20.abi, assets.wmatic);
    SUSHI = await ethers.getContractAt(IERC20.abi, assets.sushi);
    SushiLPUSDCWETH = await ethers.getContractAt(IERC20.abi, sushi.pools.usdc_weth.address);
    AMUSDC = await ethers.getContractAt(IERC20.abi, aave.aTokens.usdc);
    AMWETH = await ethers.getContractAt(IERC20.abi, aave.aTokens.weth);
    VariableUSDT = await ethers.getContractAt(IERC20.abi, aave.variableDebtTokens.dai);
    VariableWETH = await ethers.getContractAt(IERC20.abi, aave.variableDebtTokens.weth);
    let balance = await ethers.provider.getBalance(logicOwner.address);
    console.log("Matic balance: ", balance.toString());
    balance = await WMATIC.balanceOf(logicOwner.address);
    console.log("WMatic balance: ", balance.toString());
    const IUniswapV2Router = await hre.artifacts.readArtifact("IUniswapV2Router");
    const sushiswapRouter = await ethers.getContractAt(IUniswapV2Router.abi, sushi.router);
    // deposit Matic -> WMatic
    await WMatic.deposit({ value: units(500) });
    balance = await WMATIC.balanceOf(logicOwner.address);
    console.log("WMatic balance: ", balance.toString());
    // WMatic -> USDC
    await WMatic.approve(sushi.router, units(500));
    await sushiswapRouter.swapExactTokensForTokens(
      units(500),
      0,
      [assets.wmatic, assets.usdc],
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
        [assets.usdc, true],
        [assets.weth, true],
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

    await poolFactory.createFund(
      false,
      manager.address,
      "Barren Wuffet",
      "Test Fund",
      "DHTF",
      new ethers.BigNumber.from("5000"),
      new ethers.BigNumber.from("0"), // 0% streaming fee
      [
        [assets.usdc, true],
        [assets.weth, true],
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
    expect(await poolManagerLogicProxy.isSupportedAsset(assets.usdc)).to.be.true;
    expect(await poolManagerLogicProxy.isSupportedAsset(assets.weth)).to.be.true;

    //Other assets are not supported
    expect(await poolManagerLogicProxy.isSupportedAsset(assets.usdt)).to.be.false;
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

    let chainlinkEth = await ethers.getContractAt("AggregatorV3Interface", price_feeds.eth);
    let ethPrice = await chainlinkEth.latestRoundData();
    console.log("eth price: ", ethPrice[1].toString());
    console.log("updatedAt: ", ethPrice[3].toString());

    let chainlinkUsdc = await ethers.getContractAt("AggregatorV3Interface", price_feeds.usdc);
    let usdcPrice = await chainlinkUsdc.latestRoundData();
    console.log("usdc price: ", usdcPrice[1].toString());
    console.log("updatedAt: ", usdcPrice[3].toString());

    // Revert on second time
    let assetBalance = await poolManagerLogicProxy.assetBalance(assets.usdc);
    console.log("assetBalance: ", assetBalance.toString());

    // Revert on second time
    let assetValue = await poolManagerLogicProxy["assetValue(address)"](assets.usdc);
    console.log("assetValue: ", assetValue.toString());

    // Revert on second time
    totalFundValue = await poolManagerLogicProxy.totalFundValue();
    expect(totalFundValue.toString()).to.equal("0");

    await USDC.approve(poolLogicProxy.address, (200e6).toString());
    await poolLogicProxy.deposit(assets.usdc, (200e6).toString());
    let event = await depositEvent;

    expect(event.fundAddress).to.equal(poolLogicProxy.address);
    expect(event.investor).to.equal(logicOwner.address);
    checkAlmostSame(event.valueDeposited, units(200));
    checkAlmostSame(event.fundTokensReceived, units(200));
    checkAlmostSame(event.fundValue, units(200));
    checkAlmostSame(event.totalSupply, units(200));
  });

  it("should be able to swap USDC to WETH on Sushiswap.", async () => {
    // Pool balance: 200 USDC

    // First approve USDC
    approveABI = iERC20.encodeFunctionData("approve", [sushi.router, (200e6).toString()]);
    await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);

    const sourceAmount = (50e6).toString();

    const swapABI = iSushiswapV2Router.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      await getAmountOut(sushi.router, sourceAmount, [assets.usdc, assets.weth]),
      [assets.usdc, assets.weth],
      poolLogicProxy.address,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);

    await poolLogicProxy.connect(manager).execTransaction(sushi.router, swapABI);

    expect(await USDC.balanceOf(poolLogicProxy.address)).to.be.equal(150e6);
  });

  describe("Aave", () => {
    it("Should be able to deposit usdc and receive amusdc", async () => {
      // Pool balance: 150 USDC, $50 in WETH

      const amount = (100e6).toString();

      const depositABI = iLendingPool.encodeFunctionData("deposit", [assets.usdc, amount, poolLogicProxy.address, 0]);

      // add supported assets
      await poolManagerLogicProxy.connect(manager).changeAssets([[aave.lendingPool, false]], []);

      // approve usdc
      let approveABI = iERC20.encodeFunctionData("approve", [aave.lendingPool, amount]);
      await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);

      const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
      const amusdcBalanceBefore = await AMUSDC.balanceOf(poolLogicProxy.address);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      expect(usdcBalanceBefore).to.be.equal((150e6).toString());
      expect(amusdcBalanceBefore).to.be.equal(0);

      // deposit
      await poolLogicProxy.connect(manager).execTransaction(aave.lendingPool, depositABI);

      const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
      const amusdcBalanceAfter = await AMUSDC.balanceOf(poolLogicProxy.address);
      expect(usdcBalanceAfter).to.be.equal((50e6).toString());
      checkAlmostSame(amusdcBalanceAfter, 100e6);
      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
    });

    it("Should be able to deposit weth and receive amweth", async () => {
      // Pool balance: 100 USDC, $50 in WETH
      // Aave balance: 100 amUSDC

      const amount = (await WETH.balanceOf(poolLogicProxy.address)).div(2); // half of WETH balance ($25)

      const depositABI = iLendingPool.encodeFunctionData("deposit", [assets.weth, amount, poolLogicProxy.address, 0]);

      // add supported assets
      await poolManagerLogicProxy.connect(manager).changeAssets([[aave.lendingPool, false]], []);

      // approve weth
      let approveABI = iERC20.encodeFunctionData("approve", [aave.lendingPool, amount]);
      await poolLogicProxy.connect(manager).execTransaction(assets.weth, approveABI);

      const wethBalanceBefore = await WETH.balanceOf(poolLogicProxy.address);
      const amwethBalanceBefore = await AMWETH.balanceOf(poolLogicProxy.address);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      expect(amwethBalanceBefore).to.be.equal(0);

      // deposit
      await poolLogicProxy.connect(manager).execTransaction(aave.lendingPool, depositABI);

      const wethBalanceAfter = await WETH.balanceOf(poolLogicProxy.address);
      const amwethBalanceAfter = await AMWETH.balanceOf(poolLogicProxy.address);
      checkAlmostSame(wethBalanceAfter, amount);
      checkAlmostSame(amwethBalanceAfter, amount);
      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
    });

    it("Should be able to borrow USDT", async () => {
      // Pool balance: 50 USDC, $25 in WETH
      // Aave balance: 100 amUSDC, $25 in amWETH

      const amount = (50e6).toString();

      const borrowABI = iLendingPool.encodeFunctionData("borrow", [assets.usdt, amount, 2, 0, poolLogicProxy.address]);

      await poolManagerLogicProxy.connect(manager).changeAssets([[assets.usdt, false]], []);

      const usdtBalanceBefore = await USDT.balanceOf(poolLogicProxy.address);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      expect(usdtBalanceBefore).to.be.equal(0);

      // borrow
      await poolLogicProxy.connect(manager).execTransaction(aave.lendingPool, borrowABI);

      const usdtBalanceAfter = await USDT.balanceOf(poolLogicProxy.address);
      expect(usdtBalanceAfter).to.be.equal(amount);

      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
    });

    it("should be able to withdraw", async function () {
      // Pool balance: 50 USDC, $25 in WETH, 50 USDT
      // Aave balance: 100 amUSDC, $25 in amWETH, 50 debtUSDT

      // enable weth to check withdraw process
      await poolManagerLogicProxy.connect(manager).changeAssets([[assets.weth, false]], []);

      // Withdraw 40%
      let withdrawAmount = units(80);

      const usdcBalanceBefore = ethers.BigNumber.from(await USDC.balanceOf(logicOwner.address));
      const usdtBalanceBefore = ethers.BigNumber.from(await USDT.balanceOf(logicOwner.address));
      const totalFundValueBefore = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());

      checkAlmostSame(totalFundValueBefore, units(200));

      // Unapprove WETH in Sushiswap to test conditional approval logic
      approveABI = iERC20.encodeFunctionData("approve", [sushi.router, (0).toString()]);
      await poolLogicProxy.connect(manager).execTransaction(assets.weth, approveABI);

      await poolFactory.setExitCooldown(0);
      await poolLogicProxy.withdraw(withdrawAmount);

      const totalFundValueAfter = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());

      checkAlmostSame(totalFundValueAfter, totalFundValueBefore.mul(60).div(100));
      const usdcBalanceAfter = ethers.BigNumber.from(await USDC.balanceOf(logicOwner.address));
      const usdtBalanceAfter = ethers.BigNumber.from(await USDT.balanceOf(logicOwner.address));
      console.log(usdcBalanceAfter.toString(), usdcBalanceBefore.toString());
      checkAlmostSame(usdcBalanceAfter, usdcBalanceBefore.add((20e6).toString()));
      checkAlmostSame(usdtBalanceAfter, usdtBalanceBefore.add((20e6).toString()));
    });

    it("Should be able to borrow more USDT", async () => {
      // Pool balance: 30 USDC, $15 in WETH, 30 USDT
      // Aave balance: 60 amUSDC, $15 in amWETH, 30 debtUSDT

      const wethBalanceBefore = await WETH.balanceOf(poolLogicProxy.address);
      const amwethBalanceBefore = await AMWETH.balanceOf(poolLogicProxy.address);
      const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
      const usdtBalanceBefore = await USDT.balanceOf(poolLogicProxy.address);

      const amount = (10e6).toString();

      const borrowABI = iLendingPool.encodeFunctionData("borrow", [assets.usdt, amount, 2, 0, poolLogicProxy.address]);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      // borrow
      await poolLogicProxy.connect(manager).execTransaction(aave.lendingPool, borrowABI);

      const usdtBalanceAfter = await USDT.balanceOf(poolLogicProxy.address);

      checkAlmostSame(usdtBalanceAfter, usdtBalanceBefore.add(amount));
      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
    });

    it("Should be able to repay USDT", async () => {
      // Pool balance: 30 USDC, $15 in WETH, 40 USDT
      // Aave balance: 60 amUSDC, $15 in amWETH, 40 debtUSDT

      // Swap some USDC for more USDT first to be able to pay back the loan
      const sourceAmount = (10e6).toString();

      // First approve USDC
      let approveABI = iERC20.encodeFunctionData("approve", [sushi.router, sourceAmount]);
      await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);

      const swapABI = iSushiswapV2Router.encodeFunctionData("swapExactTokensForTokens", [
        sourceAmount,
        await getAmountOut(sushi.router, sourceAmount, [assets.usdc, assets.usdt]),
        [assets.usdc, assets.usdt],
        poolLogicProxy.address,
        Math.floor(Date.now() / 1000 + 100000000),
      ]);
      await poolLogicProxy.connect(manager).execTransaction(sushi.router, swapABI);

      const debtUsdtBefore = await VariableUSDT.balanceOf(poolLogicProxy.address);
      const usdtBalanceBefore = await USDT.balanceOf(poolLogicProxy.address);
      expect(debtUsdtBefore).to.be.gt(0);
      expect(usdtBalanceBefore).to.be.gt(debtUsdtBefore);

      const amount = units(10000); // max / full repayment
      const repayABI = iLendingPool.encodeFunctionData("repay", [assets.usdt, amount, 2, poolLogicProxy.address]);

      // approve usdt
      approveABI = iERC20.encodeFunctionData("approve", [aave.lendingPool, amount]);
      await poolLogicProxy.connect(manager).execTransaction(assets.usdt, approveABI);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      // repay
      await poolLogicProxy.connect(manager).execTransaction(aave.lendingPool, repayABI);

      const usdtBalanceAfter = await USDT.balanceOf(poolLogicProxy.address);

      expect(approxEq(usdtBalanceAfter, 10e6, 0.01));

      const debtUsdtAfter = await VariableUSDT.balanceOf(poolLogicProxy.address);
      expect(debtUsdtAfter).to.be.equal(0);

      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
    });

    it("Should be able to borrow WETH", async () => {
      // Pool balance: 20 USDC, $15 in WETH, 10 USDT
      // Aave balance: 60 amUSDC, $15 in amWETH

      const wethBalanceBefore = await WETH.balanceOf(poolLogicProxy.address);

      const amount = (1e14).toString(); // small amount of WETH to borrow

      const borrowABI = iLendingPool.encodeFunctionData("borrow", [assets.weth, amount, 2, 0, poolLogicProxy.address]);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      // borrow
      await poolLogicProxy.connect(manager).execTransaction(aave.lendingPool, borrowABI);

      const wethBalanceAfter = await WETH.balanceOf(poolLogicProxy.address);
      expect(wethBalanceAfter).to.be.gt(wethBalanceBefore);

      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
    });

    it("Should be able to repay WETH", async () => {
      // Pool balance: 30 USDC, $15 in WETH + some borrowed WETH, 40 USDT
      // Aave balance: 60 amUSDC, $15 in amWETH, some debtWETH

      const debtWethBefore = await VariableWETH.balanceOf(poolLogicProxy.address);
      expect(debtWethBefore).to.be.gt(0);

      const amount = units(10000); // max / full repayment

      let repayABI = iLendingPool.encodeFunctionData("repay", [assets.weth, amount, 2, poolLogicProxy.address]);

      // approve weth
      approveABI = iERC20.encodeFunctionData("approve", [aave.lendingPool, amount]);
      await poolLogicProxy.connect(manager).execTransaction(assets.weth, approveABI);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      // repay
      await poolLogicProxy.connect(manager).execTransaction(aave.lendingPool, repayABI);

      const debtWethAfter = await VariableWETH.balanceOf(poolLogicProxy.address);
      expect(debtWethAfter).to.be.equal(0);

      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
    });
  });
});
