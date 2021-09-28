const { ethers, upgrades } = require("hardhat");
const { expect, use } = require("chai");
const chaiAlmost = require("chai-almost");
const { checkAlmostSame, toBytes32, getAmountOut, units } = require("../../TestHelpers");
const { ZERO_ADDRESS, sushi, aave, assets, price_feeds } = require("../ethereum-data");

use(chaiAlmost());

describe("Aave Test", function () {
  let WETH, USDC, DAI, AUSDC, StableDAI, VariableDAI;
  let usdPriceAggregator;
  let logicOwner, manager, dao, user;
  let PoolFactory, PoolLogic, PoolManagerLogic;
  let poolFactory, poolLogic, poolManagerLogic, poolLogicProxy, poolManagerLogicProxy, fundAddress;

  before(async function () {
    [logicOwner, manager, dao, user] = await ethers.getSigners();

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
    const assetWeth = { asset: assets.weth, assetType: 0, aggregator: price_feeds.eth };
    const assetUsdt = { asset: assets.usdt, assetType: 0, aggregator: price_feeds.usdt };
    const assetDai = { asset: assets.dai, assetType: 0, aggregator: price_feeds.dai };
    const assetUsdc = { asset: assets.usdc, assetType: 0, aggregator: price_feeds.usdc };
    const assetLendingPool = { asset: aave.lendingPool, assetType: 3, aggregator: usdPriceAggregator.address };
    const assetHandlerInitAssets = [assetWeth, assetUsdt, assetDai, assetUsdc, assetLendingPool];

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

    const OpenAssetGuard = await ethers.getContractFactory("OpenAssetGuard");
    openAssetGuard = await OpenAssetGuard.deploy([]);
    await openAssetGuard.deployed();

    const UniswapV2RouterGuard = await ethers.getContractFactory("UniswapV2RouterGuard");
    uniswapV2RouterGuard = await UniswapV2RouterGuard.deploy(2, 100); // set slippage 2% for testing
    uniswapV2RouterGuard.deployed();

    const AaveLendingPoolAssetGuard = await ethers.getContractFactory("AaveLendingPoolAssetGuard");
    const aaveLendingPoolAssetGuard = await AaveLendingPoolAssetGuard.deploy(aave.protocolDataProvider);
    aaveLendingPoolAssetGuard.deployed();

    const AaveLendingPoolGuard = await ethers.getContractFactory("AaveLendingPoolGuard");
    const aaveLendingPoolGuard = await AaveLendingPoolGuard.deploy();
    aaveLendingPoolGuard.deployed();

    await governance.setAssetGuard(0, erc20Guard.address);
    await governance.setAssetGuard(3, aaveLendingPoolAssetGuard.address);
    await governance.setContractGuard(sushi.router, uniswapV2RouterGuard.address);
    await governance.setContractGuard(aave.lendingPool, aaveLendingPoolGuard.address);
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
    WETH = await ethers.getContractAt(IWETH.abi, assets.weth);
    const IERC20 = await hre.artifacts.readArtifact("IERC20");
    USDT = await ethers.getContractAt(IERC20.abi, assets.usdt);
    DAI = await ethers.getContractAt(IERC20.abi, assets.dai);
    USDC = await ethers.getContractAt(IERC20.abi, assets.usdc);
    AUSDC = await ethers.getContractAt(IERC20.abi, aave.aTokens.usdc);
    StableDAI = await ethers.getContractAt(IERC20.abi, aave.stableDebtTokens.dai);
    VariableDAI = await ethers.getContractAt(IERC20.abi, aave.variableDebtTokens.dai);
    let balance = await ethers.provider.getBalance(logicOwner.address);
    console.log("ETH balance: ", balance.toString());
    balance = await WETH.balanceOf(logicOwner.address);
    console.log("WETH balance: ", balance.toString());
    const IUniswapV2Router = await hre.artifacts.readArtifact("IUniswapV2Router");
    const sushiRouter = await ethers.getContractAt(IUniswapV2Router.abi, sushi.router);
    // deposit ETH -> WETH
    await WETH.deposit({ value: units(500) });
    balance = await WETH.balanceOf(logicOwner.address);
    console.log("WETH balance: ", balance.toString());
    // WETH -> USDC
    await WETH.approve(sushi.router, units(500));
    await sushiRouter.swapExactTokensForTokens(
      units(500),
      0,
      [assets.weth, assets.usdc],
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

    await expect(
      poolFactory.createFund(
        false,
        manager.address,
        "Barren Wuffet",
        "Test Fund",
        "DHTF",
        new ethers.BigNumber.from("6000"),
        [
          [assets.usdc, true],
          [assets.weth, true],
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
    console.log("assets.usdc price: ", usdcPrice[1].toString());
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

    await expect(poolLogicProxy.deposit(assets.usdt, (200e6).toString())).to.be.revertedWith("invalid deposit asset");

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
    const IERC20 = await hre.artifacts.readArtifact("IERC20");
    const iERC20 = new ethers.utils.Interface(IERC20.abi);
    approveABI = iERC20.encodeFunctionData("approve", [sushi.router, (200e6).toString()]);
    await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);

    const sourceAmount = (20e6).toString();
    const IUniswapV2Router = await hre.artifacts.readArtifact("IUniswapV2Router");
    const iSushiswapV2Router = new ethers.utils.Interface(IUniswapV2Router.abi);

    const swapABI = iSushiswapV2Router.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      await getAmountOut(sushi.router, sourceAmount, [assets.usdc, assets.weth]),
      [assets.usdc, assets.weth],
      poolLogicProxy.address,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);

    await poolLogicProxy.connect(manager).execTransaction(sushi.router, swapABI);

    expect(await USDC.balanceOf(poolLogicProxy.address)).to.be.equal(180e6);
  });

  describe("Aave", () => {
    it("Should be able to deposit assets.usdc and receive aave.aTokens.usdc", async () => {
      // Pool balance: 180 USDC, $20 in WETH

      const amount = (100e6).toString();

      const ILendingPool = await hre.artifacts.readArtifact("ILendingPool");
      const iLendingPool = new ethers.utils.Interface(ILendingPool.abi);
      let depositABI = iLendingPool.encodeFunctionData("deposit", [assets.usdc, amount, poolLogicProxy.address, 0]);

      await expect(poolLogicProxy.connect(manager).execTransaction(ZERO_ADDRESS, depositABI)).to.be.revertedWith(
        "non-zero address is required",
      );

      await expect(
        poolLogicProxy.connect(manager).execTransaction(poolLogicProxy.address, depositABI),
      ).to.be.revertedWith("invalid destination");

      depositABI = iLendingPool.encodeFunctionData("deposit", [aave.aTokens.usdt, amount, poolLogicProxy.address, 0]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aave.lendingPool, depositABI)).to.be.revertedWith(
        "asset not enabled in pool",
      );

      // add supported assets
      await poolManagerLogicProxy.connect(manager).changeAssets([[aave.lendingPool, false]], []);

      depositABI = iLendingPool.encodeFunctionData("deposit", [aave.aTokens.usdt, amount, poolLogicProxy.address, 0]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aave.lendingPool, depositABI)).to.be.revertedWith(
        "unsupported deposit asset",
      );

      depositABI = iLendingPool.encodeFunctionData("deposit", [assets.usdc, amount, assets.usdc, 0]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aave.lendingPool, depositABI)).to.be.revertedWith(
        "recipient is not pool",
      );

      depositABI = iLendingPool.encodeFunctionData("deposit", [assets.usdc, amount, poolLogicProxy.address, 0]);
      await expect(poolLogicProxy.connect(manager).execTransaction(assets.usdc, depositABI)).to.be.revertedWith(
        "invalid transaction",
      );

      await expect(poolLogicProxy.connect(manager).execTransaction(aave.lendingPool, depositABI)).to.be.revertedWith(
        "SafeERC20: low-level call failed",
      );

      // approve usdc
      const IERC20 = await hre.artifacts.readArtifact("IERC20");
      const iERC20 = new ethers.utils.Interface(IERC20.abi);
      let approveABI = iERC20.encodeFunctionData("approve", [aave.lendingPool, amount]);
      await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);

      const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
      const ausdcBalanceBefore = await AUSDC.balanceOf(poolLogicProxy.address);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      expect(usdcBalanceBefore).to.be.equal((180e6).toString());
      expect(ausdcBalanceBefore).to.be.equal(0);

      // deposit
      await poolLogicProxy.connect(manager).execTransaction(aave.lendingPool, depositABI);

      const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
      const ausdcBalanceAfter = await AUSDC.balanceOf(poolLogicProxy.address);
      expect(usdcBalanceAfter).to.be.equal((80e6).toString());
      checkAlmostSame(ausdcBalanceAfter, 100e6);
      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
    });

    it("Should be able to withdraw ausdc and receive usdc", async () => {
      // Pool balance: 80 USDC, 100 aUSDC, $20 in WETH

      const amount = (50e6).toString();

      const ILendingPool = await hre.artifacts.readArtifact("ILendingPool");
      const iLendingPool = new ethers.utils.Interface(ILendingPool.abi);
      let withdrawABI = iLendingPool.encodeFunctionData("withdraw", [assets.usdc, amount, poolLogicProxy.address]);

      await expect(poolLogicProxy.connect(manager).execTransaction(ZERO_ADDRESS, withdrawABI)).to.be.revertedWith(
        "non-zero address is required",
      );

      await expect(
        poolLogicProxy.connect(manager).execTransaction(poolLogicProxy.address, withdrawABI),
      ).to.be.revertedWith("invalid destination");

      withdrawABI = iLendingPool.encodeFunctionData("withdraw", [aave.aTokens.usdt, amount, poolLogicProxy.address]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aave.lendingPool, withdrawABI)).to.be.revertedWith(
        "unsupported withdraw asset",
      );
      withdrawABI = iLendingPool.encodeFunctionData("withdraw", [assets.usdc, amount, assets.usdc]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aave.lendingPool, withdrawABI)).to.be.revertedWith(
        "recipient is not pool",
      );

      withdrawABI = iLendingPool.encodeFunctionData("withdraw", [assets.usdc, amount, poolLogicProxy.address]);
      await expect(poolLogicProxy.connect(manager).execTransaction(assets.usdc, withdrawABI)).to.be.revertedWith(
        "invalid transaction",
      );

      const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
      const ausdcBalanceBefore = await AUSDC.balanceOf(poolLogicProxy.address);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      // withdraw
      await poolLogicProxy.connect(manager).execTransaction(aave.lendingPool, withdrawABI);

      const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
      const ausdcBalanceAfter = await AUSDC.balanceOf(poolLogicProxy.address);
      checkAlmostSame(ethers.BigNumber.from(usdcBalanceBefore).add(amount), usdcBalanceAfter);
      checkAlmostSame(ethers.BigNumber.from(ausdcBalanceBefore).sub(amount), ausdcBalanceAfter);

      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
    });

    it("Should be able to set reserve as collateral", async () => {
      // Pool balance: 130 USDC, $20 in WETH
      // Aave balance: 50 aUSDC

      const ILendingPool = await hre.artifacts.readArtifact("ILendingPool");
      const lendingPool = await ethers.getContractAt(ILendingPool.abi, aave.lendingPool);

      const iLendingPool = new ethers.utils.Interface(ILendingPool.abi);

      let abi = iLendingPool.encodeFunctionData("setUserUseReserveAsCollateral", [assets.usdt, true]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aave.lendingPool, abi)).to.be.revertedWith(
        "unsupported asset",
      );

      abi = iLendingPool.encodeFunctionData("setUserUseReserveAsCollateral", [assets.weth, true]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aave.lendingPool, abi)).to.be.revertedWith("19");

      abi = iLendingPool.encodeFunctionData("setUserUseReserveAsCollateral", [assets.usdc, false]);
      await poolLogicProxy.connect(manager).execTransaction(aave.lendingPool, abi);

      const userConfigBefore = await lendingPool.getUserConfiguration(poolLogicProxy.address);

      abi = iLendingPool.encodeFunctionData("setUserUseReserveAsCollateral", [assets.usdc, true]);
      await poolLogicProxy.connect(manager).execTransaction(aave.lendingPool, abi);

      const userConfigAfter = await lendingPool.getUserConfiguration(poolLogicProxy.address);
      expect(userConfigBefore).to.be.not.equal(userConfigAfter);
    });

    it("should be able to withdraw 20%", async function () {
      // Pool balance: 130 USDC, $20 in WETH
      // Aave balance: 50 aUSDC

      // Withdraw 20%
      let withdrawAmount = units(40);

      await poolFactory.setExitCooldown(0);

      const usdcBalanceBefore = ethers.BigNumber.from(await USDC.balanceOf(poolLogicProxy.address));
      const totalFundValueBefore = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());
      const userUsdcBalanceBefore = await USDC.balanceOf(logicOwner.address);

      await poolLogicProxy.withdraw(withdrawAmount);

      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore.mul(80).div(100));
      const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
      checkAlmostSame(usdcBalanceAfter, usdcBalanceBefore.sub("26000000"));
      const userUsdcBalanceAfter = await USDC.balanceOf(logicOwner.address);
      checkAlmostSame(userUsdcBalanceAfter, userUsdcBalanceBefore.add("26000000").add("10000000"));
    });

    it("Should be able to borrow DAI", async () => {
      // Pool balance: 104 USDC, $16 in WETH
      // Aave balance: 40 aUSDC

      const amount = units(25).toString();

      const ILendingPool = await hre.artifacts.readArtifact("ILendingPool");
      const iLendingPool = new ethers.utils.Interface(ILendingPool.abi);
      let borrowABI = iLendingPool.encodeFunctionData("borrow", [assets.dai, amount, 2, 0, poolLogicProxy.address]);

      await expect(poolLogicProxy.connect(manager).execTransaction(ZERO_ADDRESS, borrowABI)).to.be.revertedWith(
        "non-zero address is required",
      );

      await expect(
        poolLogicProxy.connect(manager).execTransaction(poolLogicProxy.address, borrowABI),
      ).to.be.revertedWith("invalid destination");

      borrowABI = iLendingPool.encodeFunctionData("borrow", [aave.aTokens.dai, amount, 2, 0, poolLogicProxy.address]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aave.lendingPool, borrowABI)).to.be.revertedWith(
        "unsupported borrow asset",
      );

      await poolManagerLogicProxy.connect(manager).changeAssets([[assets.dai, false]], []);

      borrowABI = iLendingPool.encodeFunctionData("borrow", [assets.dai, amount, 2, 0, assets.usdc]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aave.lendingPool, borrowABI)).to.be.revertedWith(
        "recipient is not pool",
      );

      borrowABI = iLendingPool.encodeFunctionData("borrow", [assets.dai, amount, 2, 0, poolLogicProxy.address]);
      await expect(poolLogicProxy.connect(manager).execTransaction(assets.dai, borrowABI)).to.be.revertedWith(
        "invalid transaction",
      );

      const daiBalanceBefore = await DAI.balanceOf(poolLogicProxy.address);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      expect(daiBalanceBefore).to.be.equal(0);

      // borrow
      await poolLogicProxy.connect(manager).execTransaction(aave.lendingPool, borrowABI);

      borrowABI = iLendingPool.encodeFunctionData("borrow", [assets.usdc, amount, 2, 0, poolLogicProxy.address]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aave.lendingPool, borrowABI)).to.be.revertedWith(
        "borrowing asset exists",
      );

      const daiBalanceAfter = await DAI.balanceOf(poolLogicProxy.address);
      expect(daiBalanceAfter).to.be.equal(units(25));

      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
    });

    it("Should be able to repay DAI", async () => {
      // Pool balance: 104 USDC, 25 DAI, $16 in WETH
      // Aave balance: 40 aUSDC, 25 debtDAI

      const amount = units(10);

      const ILendingPool = await hre.artifacts.readArtifact("ILendingPool");
      const iLendingPool = new ethers.utils.Interface(ILendingPool.abi);
      let repayABI = iLendingPool.encodeFunctionData("repay", [assets.dai, amount, 2, poolLogicProxy.address]);

      await expect(poolLogicProxy.connect(manager).execTransaction(ZERO_ADDRESS, repayABI)).to.be.revertedWith(
        "non-zero address is required",
      );

      await expect(
        poolLogicProxy.connect(manager).execTransaction(poolLogicProxy.address, repayABI),
      ).to.be.revertedWith("invalid destination");

      repayABI = iLendingPool.encodeFunctionData("repay", [aave.aTokens.dai, amount, 2, poolLogicProxy.address]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aave.lendingPool, repayABI)).to.be.revertedWith(
        "unsupported repay asset",
      );

      repayABI = iLendingPool.encodeFunctionData("repay", [assets.dai, amount, 2, assets.usdc]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aave.lendingPool, repayABI)).to.be.revertedWith(
        "recipient is not pool",
      );

      repayABI = iLendingPool.encodeFunctionData("repay", [assets.dai, amount, 2, poolLogicProxy.address]);
      await expect(poolLogicProxy.connect(manager).execTransaction(assets.dai, repayABI)).to.be.revertedWith(
        "invalid transaction",
      );

      await expect(poolLogicProxy.connect(manager).execTransaction(aave.lendingPool, repayABI)).to.be.revertedWith(
        "SafeERC20: low-level call failed",
      );

      // approve dai
      const IERC20 = await hre.artifacts.readArtifact("IERC20");
      const iERC20 = new ethers.utils.Interface(IERC20.abi);
      let approveABI = iERC20.encodeFunctionData("approve", [aave.lendingPool, amount]);
      await poolLogicProxy.connect(manager).execTransaction(assets.dai, approveABI);

      const daiBalanceBefore = await DAI.balanceOf(poolLogicProxy.address);
      expect(daiBalanceBefore).to.be.equal(units(25));

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      // repay
      await poolLogicProxy.connect(manager).execTransaction(aave.lendingPool, repayABI);

      const daiBalanceAfter = await DAI.balanceOf(poolLogicProxy.address);
      expect(daiBalanceAfter).to.be.equal(units(15));

      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
    });

    it("should be able to withdraw", async function () {
      // Pool balance: 104 USDC, 15 DAI, $16 in WETH
      // Aave balance: 40 aUSDC, 15 debtDAI

      // Withdraw 10%
      let withdrawAmount = units(16);

      const usdcBalanceBefore = ethers.BigNumber.from(await USDC.balanceOf(logicOwner.address));
      const totalFundValueBefore = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());

      checkAlmostSame(totalFundValueBefore, units(160));

      await poolLogicProxy.withdraw(withdrawAmount);

      const totalFundValueAfter = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());

      checkAlmostSame(totalFundValueAfter, totalFundValueBefore.mul(90).div(100));
      const usdcBalanceAfter = ethers.BigNumber.from(await USDC.balanceOf(logicOwner.address));
      checkAlmostSame(usdcBalanceAfter, usdcBalanceBefore.add((12e6).toString()));
    });

    it("should be able to swap borrow rate mode", async function () {
      const ILendingPool = await hre.artifacts.readArtifact("ILendingPool");
      const iLendingPool = new ethers.utils.Interface(ILendingPool.abi);
      let swapRateABI = iLendingPool.encodeFunctionData("swapBorrowRateMode", [assets.usdc, 1]);

      await expect(poolLogicProxy.connect(manager).execTransaction(ZERO_ADDRESS, swapRateABI)).to.be.revertedWith(
        "non-zero address is required",
      );

      await expect(
        poolLogicProxy.connect(manager).execTransaction(poolLogicProxy.address, swapRateABI),
      ).to.be.revertedWith("invalid destination");

      swapRateABI = iLendingPool.encodeFunctionData("swapBorrowRateMode", [aave.aTokens.dai, 1]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aave.lendingPool, swapRateABI)).to.be.revertedWith(
        "unsupported asset",
      );

      swapRateABI = iLendingPool.encodeFunctionData("swapBorrowRateMode", [assets.usdc, 1]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aave.lendingPool, swapRateABI)).to.be.revertedWith(
        "17",
      );

      expect(await VariableDAI.balanceOf(poolLogicProxy.address)).to.gt(0);
      expect(await StableDAI.balanceOf(poolLogicProxy.address)).to.equal(0);

      swapRateABI = iLendingPool.encodeFunctionData("swapBorrowRateMode", [assets.dai, 2]);
      await poolLogicProxy.connect(manager).execTransaction(aave.lendingPool, swapRateABI);

      expect(await VariableDAI.balanceOf(poolLogicProxy.address)).to.equal(0);
      expect(await StableDAI.balanceOf(poolLogicProxy.address)).to.gt(0);

      swapRateABI = iLendingPool.encodeFunctionData("swapBorrowRateMode", [assets.dai, 1]);
      await poolLogicProxy.connect(manager).execTransaction(aave.lendingPool, swapRateABI);

      expect(await VariableDAI.balanceOf(poolLogicProxy.address)).to.gt(0);
      expect(await StableDAI.balanceOf(poolLogicProxy.address)).to.equal(0);
    });

    it("should be able to swap borrow rate mode", async function () {
      const ILendingPool = await hre.artifacts.readArtifact("ILendingPool");
      const iLendingPool = new ethers.utils.Interface(ILendingPool.abi);
      let rebalanceAPI = iLendingPool.encodeFunctionData("rebalanceStableBorrowRate", [
        assets.usdc,
        poolLogicProxy.address,
      ]);

      await expect(poolLogicProxy.connect(manager).execTransaction(ZERO_ADDRESS, rebalanceAPI)).to.be.revertedWith(
        "non-zero address is required",
      );

      await expect(
        poolLogicProxy.connect(manager).execTransaction(poolLogicProxy.address, rebalanceAPI),
      ).to.be.revertedWith("invalid destination");

      rebalanceAPI = iLendingPool.encodeFunctionData("rebalanceStableBorrowRate", [
        aave.aTokens.dai,
        poolLogicProxy.address,
      ]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aave.lendingPool, rebalanceAPI)).to.be.revertedWith(
        "unsupported asset",
      );

      rebalanceAPI = iLendingPool.encodeFunctionData("rebalanceStableBorrowRate", [assets.usdc, assets.weth]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aave.lendingPool, rebalanceAPI)).to.be.revertedWith(
        "user is not pool",
      );

      rebalanceAPI = iLendingPool.encodeFunctionData("rebalanceStableBorrowRate", [
        assets.usdc,
        poolLogicProxy.address,
      ]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aave.lendingPool, rebalanceAPI)).to.be.revertedWith(
        "22",
      );

      rebalanceAPI = iLendingPool.encodeFunctionData("rebalanceStableBorrowRate", [assets.dai, poolLogicProxy.address]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aave.lendingPool, rebalanceAPI)).to.be.revertedWith(
        "22",
      );
    });
  });
});
