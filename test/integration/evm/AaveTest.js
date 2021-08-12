const { ethers, upgrades } = require("hardhat");
const { expect, use } = require("chai");
const chaiAlmost = require("chai-almost");
const { checkAlmostSame, toBytes32 } = require("../../TestHelpers");

use(chaiAlmost());

const units = (value) => ethers.utils.parseUnits(value.toString());

// sushiswap
const sushiswapV2Factory = "0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac";
const sushiswapV2Router = "0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F";

// aave
const aaveProtocolDataProvider = "0x057835Ad21a177dbdd3090bB1CAE03EaCF78Fc6d";
const aaveLendingPool = "0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9";

// For mainnet
const weth = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
const usdc = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
const usdt = "0xdAC17F958D2ee523a2206206994597C13D831ec7";
const dai = "0x6B175474E89094C44Da98b954EedeAC495271d0F";

const aweth = "0x030bA81f1c18d280636F32af80b9AAd02Cf0854e";
const ausdc = "0xBcca60bB61934080951369a648Fb03DF4F96263C";
const ausdt = "0x3Ed3B47Dd13EC9a98b44e6204A523E766B225811";
const adai = "0x028171bCA77440897B824Ca71D1c56caC55b68A3";

const stableDebtDai = "0x778A13D3eeb110A4f7bb6529F99c000119a08E92";
const variableDebtDai = "0x6C3c78838c761c6Ac7bE9F59fe808ea2A6E4379d";

const eth_price_feed = "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419";
const usdc_price_feed = "0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6";
const usdt_price_feed = "0x3E7d1eAB13ad0104d2750B8863b489D65364e32D";
const dai_price_feed = "0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9";

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

describe("Aave Test", function () {
  let WETH, USDC, USDT, DAI, AUSDC, StableDAI, VariableDAI;
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

    PoolLogic = await ethers.getContractFactory("PoolLogic");
    poolLogic = await PoolLogic.deploy();

    PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
    poolManagerLogic = await PoolManagerLogic.deploy();
    // Deploy USD Price Aggregator
    const USDPriceAggregator = await ethers.getContractFactory("USDPriceAggregator");
    usdPriceAggregator = await USDPriceAggregator.deploy();
    // Initialize Asset Price Consumer
    const assetWeth = { asset: weth, assetType: 0, aggregator: eth_price_feed };
    const assetUsdt = { asset: usdt, assetType: 0, aggregator: usdt_price_feed };
    const assetDai = { asset: dai, assetType: 0, aggregator: dai_price_feed };
    const assetUsdc = { asset: usdc, assetType: 0, aggregator: usdc_price_feed };
    const assetLendingPool = { asset: aaveLendingPool, assetType: 3, aggregator: usdPriceAggregator.address };
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
    const ERC20Guard = await ethers.getContractFactory("ERC20Guard");
    erc20Guard = await ERC20Guard.deploy();
    erc20Guard.deployed();

    const OpenAssetGuard = await ethers.getContractFactory("OpenAssetGuard");
    openAssetGuard = await OpenAssetGuard.deploy([]);
    await openAssetGuard.deployed();

    const UniswapV2RouterGuard = await ethers.getContractFactory("UniswapV2RouterGuard");
    uniswapV2RouterGuard = await UniswapV2RouterGuard.deploy(100, 100); // set slippage 100% for testing
    uniswapV2RouterGuard.deployed();

    const AaveLendingPoolAssetGuard = await ethers.getContractFactory("AaveLendingPoolAssetGuard");
    const aaveLendingPoolAssetGuard = await AaveLendingPoolAssetGuard.deploy(aaveProtocolDataProvider);
    aaveLendingPoolAssetGuard.deployed();

    const AaveLendingPoolGuard = await ethers.getContractFactory("AaveLendingPoolGuard");
    const aaveLendingPoolGuard = await AaveLendingPoolGuard.deploy();
    aaveLendingPoolGuard.deployed();

    await governance.setAssetGuard(0, erc20Guard.address);
    await governance.setAssetGuard(3, aaveLendingPoolAssetGuard.address);
    await governance.setContractGuard(sushiswapV2Router, uniswapV2RouterGuard.address);
    await governance.setContractGuard(aaveLendingPool, aaveLendingPoolGuard.address);
    await governance.setAddresses([
      [toBytes32("swapRouter"), sushiswapV2Router],
      [toBytes32("aaveProtocolDataProvider"), aaveProtocolDataProvider],
      [toBytes32("weth"), weth],
      [toBytes32("openAssetGuard"), openAssetGuard.address],
    ]);
  });

  it("Should be able to get USDC", async function () {
    const IWETH = await hre.artifacts.readArtifact("IWETH");
    WETH = await ethers.getContractAt(IWETH.abi, weth);
    const IERC20 = await hre.artifacts.readArtifact("IERC20");
    USDT = await ethers.getContractAt(IERC20.abi, usdt);
    DAI = await ethers.getContractAt(IERC20.abi, dai);
    USDC = await ethers.getContractAt(IERC20.abi, usdc);
    AUSDC = await ethers.getContractAt(IERC20.abi, ausdc);
    StableDAI = await ethers.getContractAt(IERC20.abi, stableDebtDai);
    VariableDAI = await ethers.getContractAt(IERC20.abi, variableDebtDai);
    let balance = await ethers.provider.getBalance(logicOwner.address);
    console.log("ETH balance: ", balance.toString());
    balance = await WETH.balanceOf(logicOwner.address);
    console.log("WETH balance: ", balance.toString());
    const IUniswapV2Router = await hre.artifacts.readArtifact("IUniswapV2Router");
    const sushiswapRouter = await ethers.getContractAt(IUniswapV2Router.abi, sushiswapV2Router);
    // deposit ETH -> WETH
    await WETH.deposit({ value: units(500) });
    balance = await WETH.balanceOf(logicOwner.address);
    console.log("WETH balance: ", balance.toString());
    // WETH -> USDC
    await WETH.approve(sushiswapV2Router, units(500));
    await sushiswapRouter.swapExactTokensForTokens(
      units(500),
      0,
      [weth, usdc],
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

    await expect(poolLogicProxy.deposit(usdt, (200e6).toString())).to.be.revertedWith("invalid deposit asset");

    await USDC.approve(poolLogicProxy.address, (200e6).toString());
    await poolLogicProxy.deposit(usdc, (200e6).toString());
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
    approveABI = iERC20.encodeFunctionData("approve", [sushiswapV2Router, (200e6).toString()]);
    await poolLogicProxy.connect(manager).execTransaction(usdc, approveABI);

    const sourceAmount = (20e6).toString();
    const IUniswapV2Router = await hre.artifacts.readArtifact("IUniswapV2Router");
    const iSushiswapV2Router = new ethers.utils.Interface(IUniswapV2Router.abi);

    const swapABI = iSushiswapV2Router.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      0,
      [usdc, weth],
      poolLogicProxy.address,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);

    await poolLogicProxy.connect(manager).execTransaction(sushiswapV2Router, swapABI);

    expect(await USDC.balanceOf(poolLogicProxy.address)).to.be.equal(180e6);
  });

  describe("Aave", () => {
    it("Should be able to deposit usdc and receive ausdc", async () => {
      // Pool balance: 180 USDC, $20 in WETH

      const amount = (100e6).toString();

      const ILendingPool = await hre.artifacts.readArtifact("ILendingPool");
      const iLendingPool = new ethers.utils.Interface(ILendingPool.abi);
      let depositABI = iLendingPool.encodeFunctionData("deposit", [usdc, amount, poolLogicProxy.address, 0]);

      await expect(poolLogicProxy.connect(manager).execTransaction(ZERO_ADDRESS, depositABI)).to.be.revertedWith(
        "non-zero address is required",
      );

      await expect(
        poolLogicProxy.connect(manager).execTransaction(poolLogicProxy.address, depositABI),
      ).to.be.revertedWith("invalid transaction");

      depositABI = iLendingPool.encodeFunctionData("deposit", [ausdt, amount, poolLogicProxy.address, 0]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, depositABI)).to.be.revertedWith(
        "asset not enabled in pool",
      );

      // add supported assets
      await poolManagerLogicProxy.connect(manager).changeAssets([[aaveLendingPool, false]], []);

      depositABI = iLendingPool.encodeFunctionData("deposit", [ausdt, amount, poolLogicProxy.address, 0]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, depositABI)).to.be.revertedWith(
        "unsupported deposit asset",
      );

      depositABI = iLendingPool.encodeFunctionData("deposit", [usdc, amount, usdc, 0]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, depositABI)).to.be.revertedWith(
        "recipient is not pool",
      );

      depositABI = iLendingPool.encodeFunctionData("deposit", [usdc, amount, poolLogicProxy.address, 0]);
      await expect(poolLogicProxy.connect(manager).execTransaction(usdc, depositABI)).to.be.revertedWith(
        "invalid transaction",
      );

      await expect(poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, depositABI)).to.be.revertedWith(
        "SafeERC20: low-level call failed",
      );

      // approve usdc
      const IERC20 = await hre.artifacts.readArtifact("IERC20");
      const iERC20 = new ethers.utils.Interface(IERC20.abi);
      let approveABI = iERC20.encodeFunctionData("approve", [aaveLendingPool, amount]);
      await poolLogicProxy.connect(manager).execTransaction(usdc, approveABI);

      const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
      const ausdcBalanceBefore = await AUSDC.balanceOf(poolLogicProxy.address);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      expect(usdcBalanceBefore).to.be.equal((180e6).toString());
      expect(ausdcBalanceBefore).to.be.equal(0);

      // deposit
      await poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, depositABI);

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
      let withdrawABI = iLendingPool.encodeFunctionData("withdraw", [usdc, amount, poolLogicProxy.address]);

      await expect(poolLogicProxy.connect(manager).execTransaction(ZERO_ADDRESS, withdrawABI)).to.be.revertedWith(
        "non-zero address is required",
      );

      await expect(
        poolLogicProxy.connect(manager).execTransaction(poolLogicProxy.address, withdrawABI),
      ).to.be.revertedWith("invalid transaction");

      withdrawABI = iLendingPool.encodeFunctionData("withdraw", [ausdt, amount, poolLogicProxy.address]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, withdrawABI)).to.be.revertedWith(
        "unsupported withdraw asset",
      );
      withdrawABI = iLendingPool.encodeFunctionData("withdraw", [usdc, amount, usdc]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, withdrawABI)).to.be.revertedWith(
        "recipient is not pool",
      );

      withdrawABI = iLendingPool.encodeFunctionData("withdraw", [usdc, amount, poolLogicProxy.address]);
      await expect(poolLogicProxy.connect(manager).execTransaction(usdc, withdrawABI)).to.be.revertedWith(
        "invalid transaction",
      );

      const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
      const ausdcBalanceBefore = await AUSDC.balanceOf(poolLogicProxy.address);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      // withdraw
      await poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, withdrawABI);

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
      const lendingPool = await ethers.getContractAt(ILendingPool.abi, aaveLendingPool);

      const iLendingPool = new ethers.utils.Interface(ILendingPool.abi);

      let abi = iLendingPool.encodeFunctionData("setUserUseReserveAsCollateral", [usdt, true]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, abi)).to.be.revertedWith(
        "unsupported asset",
      );

      abi = iLendingPool.encodeFunctionData("setUserUseReserveAsCollateral", [weth, true]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, abi)).to.be.revertedWith("19");

      abi = iLendingPool.encodeFunctionData("setUserUseReserveAsCollateral", [usdc, false]);
      await poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, abi);

      const userConfigBefore = await lendingPool.getUserConfiguration(poolLogicProxy.address);

      abi = iLendingPool.encodeFunctionData("setUserUseReserveAsCollateral", [usdc, true]);
      await poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, abi);

      const userConfigAfter = await lendingPool.getUserConfiguration(poolLogicProxy.address);
      expect(userConfigBefore).to.be.not.equal(userConfigAfter);
    });

    it("should be able to withdraw 20%", async function () {
      // Pool balance: 130 USDC, $20 in WETH
      // Aave balance: 50 aUSDC

      // Withdraw 20%
      let withdrawAmount = units(40);

      await expect(poolLogicProxy.withdraw(withdrawAmount)).to.be.revertedWith("cooldown active");

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
      let borrowABI = iLendingPool.encodeFunctionData("borrow", [dai, amount, 2, 0, poolLogicProxy.address]);

      await expect(poolLogicProxy.connect(manager).execTransaction(ZERO_ADDRESS, borrowABI)).to.be.revertedWith(
        "non-zero address is required",
      );

      await expect(
        poolLogicProxy.connect(manager).execTransaction(poolLogicProxy.address, borrowABI),
      ).to.be.revertedWith("invalid transaction");

      borrowABI = iLendingPool.encodeFunctionData("borrow", [adai, amount, 2, 0, poolLogicProxy.address]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, borrowABI)).to.be.revertedWith(
        "unsupported borrow asset",
      );

      await poolManagerLogicProxy.connect(manager).changeAssets([[dai, false]], []);

      borrowABI = iLendingPool.encodeFunctionData("borrow", [dai, amount, 2, 0, usdc]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, borrowABI)).to.be.revertedWith(
        "recipient is not pool",
      );

      borrowABI = iLendingPool.encodeFunctionData("borrow", [dai, amount, 2, 0, poolLogicProxy.address]);
      await expect(poolLogicProxy.connect(manager).execTransaction(dai, borrowABI)).to.be.revertedWith(
        "invalid transaction",
      );

      const daiBalanceBefore = await DAI.balanceOf(poolLogicProxy.address);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      expect(daiBalanceBefore).to.be.equal(0);

      // borrow
      await poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, borrowABI);

      borrowABI = iLendingPool.encodeFunctionData("borrow", [usdc, amount, 2, 0, poolLogicProxy.address]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, borrowABI)).to.be.revertedWith(
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
      let repayABI = iLendingPool.encodeFunctionData("repay", [dai, amount, 2, poolLogicProxy.address]);

      await expect(poolLogicProxy.connect(manager).execTransaction(ZERO_ADDRESS, repayABI)).to.be.revertedWith(
        "non-zero address is required",
      );

      await expect(
        poolLogicProxy.connect(manager).execTransaction(poolLogicProxy.address, repayABI),
      ).to.be.revertedWith("invalid transaction");

      repayABI = iLendingPool.encodeFunctionData("repay", [adai, amount, 2, poolLogicProxy.address]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, repayABI)).to.be.revertedWith(
        "unsupported repay asset",
      );

      repayABI = iLendingPool.encodeFunctionData("repay", [dai, amount, 2, usdc]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, repayABI)).to.be.revertedWith(
        "recipient is not pool",
      );

      repayABI = iLendingPool.encodeFunctionData("repay", [dai, amount, 2, poolLogicProxy.address]);
      await expect(poolLogicProxy.connect(manager).execTransaction(dai, repayABI)).to.be.revertedWith(
        "invalid transaction",
      );

      await expect(poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, repayABI)).to.be.revertedWith(
        "SafeERC20: low-level call failed",
      );

      // approve dai
      const IERC20 = await hre.artifacts.readArtifact("IERC20");
      const iERC20 = new ethers.utils.Interface(IERC20.abi);
      let approveABI = iERC20.encodeFunctionData("approve", [aaveLendingPool, amount]);
      await poolLogicProxy.connect(manager).execTransaction(dai, approveABI);

      const daiBalanceBefore = await DAI.balanceOf(poolLogicProxy.address);
      expect(daiBalanceBefore).to.be.equal(units(25));

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      // repay
      await poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, repayABI);

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
      let swapRateABI = iLendingPool.encodeFunctionData("swapBorrowRateMode", [usdc, 1]);

      await expect(poolLogicProxy.connect(manager).execTransaction(ZERO_ADDRESS, swapRateABI)).to.be.revertedWith(
        "non-zero address is required",
      );

      await expect(
        poolLogicProxy.connect(manager).execTransaction(poolLogicProxy.address, swapRateABI),
      ).to.be.revertedWith("invalid transaction");

      swapRateABI = iLendingPool.encodeFunctionData("swapBorrowRateMode", [adai, 1]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, swapRateABI)).to.be.revertedWith(
        "unsupported asset",
      );

      swapRateABI = iLendingPool.encodeFunctionData("swapBorrowRateMode", [usdc, 1]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, swapRateABI)).to.be.revertedWith(
        "17",
      );

      expect(await VariableDAI.balanceOf(poolLogicProxy.address)).to.gt(0);
      expect(await StableDAI.balanceOf(poolLogicProxy.address)).to.equal(0);

      swapRateABI = iLendingPool.encodeFunctionData("swapBorrowRateMode", [dai, 2]);
      await poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, swapRateABI);

      expect(await VariableDAI.balanceOf(poolLogicProxy.address)).to.equal(0);
      expect(await StableDAI.balanceOf(poolLogicProxy.address)).to.gt(0);

      swapRateABI = iLendingPool.encodeFunctionData("swapBorrowRateMode", [dai, 1]);
      await poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, swapRateABI);

      expect(await VariableDAI.balanceOf(poolLogicProxy.address)).to.gt(0);
      expect(await StableDAI.balanceOf(poolLogicProxy.address)).to.equal(0);
    });

    it("should be able to swap borrow rate mode", async function () {
      const ILendingPool = await hre.artifacts.readArtifact("ILendingPool");
      const iLendingPool = new ethers.utils.Interface(ILendingPool.abi);
      let rebalanceAPI = iLendingPool.encodeFunctionData("rebalanceStableBorrowRate", [usdc, poolLogicProxy.address]);

      await expect(poolLogicProxy.connect(manager).execTransaction(ZERO_ADDRESS, rebalanceAPI)).to.be.revertedWith(
        "non-zero address is required",
      );

      await expect(
        poolLogicProxy.connect(manager).execTransaction(poolLogicProxy.address, rebalanceAPI),
      ).to.be.revertedWith("invalid transaction");

      rebalanceAPI = iLendingPool.encodeFunctionData("rebalanceStableBorrowRate", [adai, poolLogicProxy.address]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, rebalanceAPI)).to.be.revertedWith(
        "unsupported asset",
      );

      rebalanceAPI = iLendingPool.encodeFunctionData("rebalanceStableBorrowRate", [usdc, weth]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, rebalanceAPI)).to.be.revertedWith(
        "user is not pool",
      );

      rebalanceAPI = iLendingPool.encodeFunctionData("rebalanceStableBorrowRate", [usdc, poolLogicProxy.address]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, rebalanceAPI)).to.be.revertedWith(
        "22",
      );

      rebalanceAPI = iLendingPool.encodeFunctionData("rebalanceStableBorrowRate", [dai, poolLogicProxy.address]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, rebalanceAPI)).to.be.revertedWith(
        "22",
      );
    });
  });
});
