const { ethers, upgrades } = require("hardhat");
const { expect, use } = require("chai");
const chaiAlmost = require("chai-almost");

use(chaiAlmost());

const units = (value) => ethers.utils.parseUnits(value.toString());

const sushiswapV2Router = "0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506";

// For mainnet
const wmatic = "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270";
const weth = "0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619";
const usdc = "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174";
const usdt = "0xc2132D05D31c914a87C6611C10748AEb04B58e8F";
const sushiToken = "0x0b3F868E0BE5597D5DB7fEB59E1CADBb0fdDa50a";
const matic_price_feed = "0xAB594600376Ec9fD91F8e885dADF0CE036862dE0";
const eth_price_feed = "0xF9680D99D6C9589e2a93a78A04A279e509205945";
const usdc_price_feed = "0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7";
const usdt_price_feed = "0x0A6513e40db6EB1b165753AD52E80663aeA50545";
const sushi_price_feed = "0x49B0c695039243BBfEb8EcD054EB70061fd54aa0";

const sushiLpUsdcWeth = "0x34965ba0ac2451A34a0471F04CCa3F990b8dea27";

describe("PoolPerformance", function () {
  let WMatic, WETH, USDC, USDT, SushiLPUSDCWETH, SUSHI;
  let sushiLPAggregator, sushiMiniChefV2Guard;
  let logicOwner, manager, dao, user;
  let PoolFactory, PoolLogic, PoolManagerLogic;
  let poolFactory,
    poolLogic,
    poolManagerLogic,
    poolLogicProxy,
    poolPerformanceProxy,
    poolManagerLogicProxy,
    fundAddress;

  before(async function () {
    [logicOwner, manager, dao, user] = await ethers.getSigners();

    const AssetHandlerLogic = await ethers.getContractFactory("AssetHandler");

    const Governance = await ethers.getContractFactory("Governance");
    let governance = await Governance.deploy();
    console.log("governance deployed to:", governance.address);

    const PoolPerformance = await ethers.getContractFactory("PoolPerformance");
    const poolPerformance = await PoolPerformance.deploy();
    poolPerformanceProxy = await PoolPerformance.attach(poolPerformance.address);

    PoolLogic = await ethers.getContractFactory("PoolLogic");
    poolLogic = await PoolLogic.deploy();

    PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
    poolManagerLogic = await PoolManagerLogic.deploy();

    // Initialize Asset Price Consumer
    const assetWmatic = { asset: wmatic, assetType: 0, aggregator: matic_price_feed };
    const assetWeth = { asset: weth, assetType: 0, aggregator: eth_price_feed };
    const assetUsdt = { asset: usdt, assetType: 0, aggregator: usdt_price_feed };
    const assetUsdc = { asset: usdc, assetType: 0, aggregator: usdc_price_feed };
    const assetSushi = { asset: sushiToken, assetType: 0, aggregator: sushi_price_feed };
    const assetHandlerInitAssets = [assetWmatic, assetWeth, assetUsdt, assetUsdc, assetSushi];

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
      poolPerformance.address,
    ]);
    await poolFactory.deployed();

    // // Deploy Sushi LP Aggregator
    // const UniV2LPAggregator = await ethers.getContractFactory("UniV2LPAggregator");
    // sushiLPAggregator = await UniV2LPAggregator.deploy(sushiLpUsdcWeth, poolFactory.address);
    // const assetSushiLPWethUsdc = { asset: sushiLpUsdcWeth, assetType: 2, aggregator: sushiLPAggregator.address };
    // await assetHandler.addAssets([assetSushiLPWethUsdc]);

    const ERC20Guard = await ethers.getContractFactory("ERC20Guard");
    erc20Guard = await ERC20Guard.deploy();
    erc20Guard.deployed();

    // const UniswapV2RouterGuard = await ethers.getContractFactory("UniswapV2RouterGuard");
    // uniswapV2RouterGuard = await UniswapV2RouterGuard.deploy(2, 100); // set slippage 2% for testing
    // uniswapV2RouterGuard.deployed();

    // const SushiMiniChefV2Guard = await ethers.getContractFactory("SushiMiniChefV2Guard");
    // sushiMiniChefV2Guard = await SushiMiniChefV2Guard.deploy(sushiToken, wmatic);
    // sushiMiniChefV2Guard.deployed();

    // const SushiLPAssetGuard = await ethers.getContractFactory("SushiLPAssetGuard");
    // sushiLPAssetGuard = await SushiLPAssetGuard.deploy(sushiMiniChefV2); // initialise with Sushi staking pool Id
    // sushiLPAssetGuard.deployed();

    await governance.setAssetGuard(0, erc20Guard.address);
    // await governance.setAssetGuard(2, sushiLPAssetGuard.address);
    // await governance.setContractGuard(sushiswapV2Router, uniswapV2RouterGuard.address);
    // await governance.setContractGuard(sushiMiniChefV2, sushiMiniChefV2Guard.address);
  });

  it("Should be able to get USDC", async function () {
    const IWETH = await hre.artifacts.readArtifact("IWETH");
    WMatic = await ethers.getContractAt(IWETH.abi, wmatic);
    const IERC20 = await hre.artifacts.readArtifact("IERC20");
    USDT = await ethers.getContractAt(IERC20.abi, usdt);
    USDC = await ethers.getContractAt(IERC20.abi, usdc);
    WETH = await ethers.getContractAt(IERC20.abi, weth);
    WMATIC = await ethers.getContractAt(IERC20.abi, wmatic);
    SUSHI = await ethers.getContractAt(IERC20.abi, sushiToken);
    SushiLPUSDCWETH = await ethers.getContractAt(IERC20.abi, sushiLpUsdcWeth);
    let balance = await ethers.provider.getBalance(logicOwner.address);
    console.log("Matic balance: ", balance.toString());
    balance = await WMATIC.balanceOf(logicOwner.address);
    console.log("WMatic balance: ", balance.toString());
    const IUniswapV2Router = await hre.artifacts.readArtifact("IUniswapV2Router");
    const sushiswapRouter = await ethers.getContractAt(IUniswapV2Router.abi, sushiswapV2Router);
    // deposit Matic -> WMatic
    await WMatic.deposit({ value: units(500) });
    balance = await WMATIC.balanceOf(logicOwner.address);
    console.log("WMatic balance: ", balance.toString());
    // WMatic -> USDC
    await WMatic.approve(sushiswapV2Router, units(500));
    await sushiswapRouter.swapExactTokensForTokens(
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
    await poolFactory.createFund(
      false,
      manager.address,
      "Barren Wuffet",
      "Test Fund",
      "DHTF",
      new ethers.BigNumber.from("5000"),
      [[usdc, true]],
    );

    const funds = await poolFactory.getDeployedFunds();
    poolLogicProxy = await PoolLogic.attach(funds[0]);
  });

  it("should be able to deposit", async function () {
    await USDC.approve(poolLogicProxy.address, (100e6).toString());
    // Deposit $1 conventional way
    await poolLogicProxy.deposit(usdc, (100e6).toString());
    // Check tokenPriceAdjustForPerformance() should be $1
    expect((await poolPerformanceProxy.tokenPrice(poolLogicProxy.address)).toString()).to.equal((1e18).toString());
    expect((await poolPerformanceProxy.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
      (1e18).toString(),
    );
    // Check hasDirectDeposit() == FALSE
    expect(await poolPerformanceProxy.hasDirectDeposit(poolLogicProxy.address)).to.equal(false);

    // Deposit $1 directly
    await USDC.transfer(poolLogicProxy.address, (100e6).toString());
    // expect((await poolPerformanceProxy.directDepositFactor2(poolLogicProxy.address)).toString()).to.equal(5e17);
    // Check TokenPrice() should be $2
    expect((await poolPerformanceProxy.tokenPrice(poolLogicProxy.address)).toString()).to.equal((2e18).toString());
    // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor 0.5)
    expect((await poolPerformanceProxy.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
      (1e18).toString(),
    );
  });

  describe("Only Standard ERC20", () => {
    // Create Fund, no management fee, enable usdc
    // Deposit $1 conventional way
    // Check tokenPriceAdjustForPerformance() should be $1
    // Check hasDirectDeposit() == FALSE
    // Deposit $1 directly
    // Check hasDirectDeposit() == TRUE
    // Check TokenPrice() should be $2
    // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor 0.5)
    // Call recordDirectDepositValue
    // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor 0.5)
    // Deposit $1 conventional way
    // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor 0.5)
    it("tokenPriceAdjustForPerformance", async () => {
      // // Check tokenPriceAdjustForPerformance() should be $1
      // let tokenPriceAdjustedForPerformance = await poolPerformanceProxy.tokenPriceAdjustedForPerformance(poolLogic.address);
      // await expect(tokenPriceAdjustedForPerformance).to.equal((1e18).toString())
    });

    // Create Fund, with 20% management fee, enable usdc
    // Deposit $1 conventional way
    // Check tokenPriceAdjustedForPerformanceAndManagerFee() should be $1
    // Check hasDirectDeposit() == FALSE
    // Deposit $1 directly
    // Check hasDirectDeposit() == TRUE
    // Check TokenPrice() should be $2
    // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor 0.5)
    // Check tokenPriceAdjustedForPerformanceAndManagerFee == $2 - .04 / 2 = $0.8; (i.e directDepositFactor 0.5)
    // Call recordDirectDepositValue
    // Check tokenPriceAdjustedForPerformanceAndManagerFee == $2 - .04 / 2 = $0.8; (i.e directDepositFactor 0.5)
    // Deposit $1 conventional way
    // Check tokenPriceAdjustedForPerformanceAndManagerFee == $2 - .04 / 2 = $0.8; (i.e directDepositFactor 0.5)
    it("tokenPriceAdjustedForPerformanceAndManagerFee", () => {});

    // In this test we make sure users can withdraw without disrupting the directDeposit detection
    // Create Fund, no management fee, enable usdc
    // Deposit $1 conventional way
    // Check tokenPriceAdjustForPerformance() should be $1
    // Check hasDirectDeposit() == FALSE
    // Deposit $1 directly
    // Check hasDirectDeposit() == TRUE
    // Check TokenPrice() should be $2
    // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor 0.5)
    // Deposit $1 conventional way (store as newTokensIssued)
    // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor 0.5)
    // Withdraw newTokensIssued (should not affect tokenPriceAdjustedForPerformance)
    // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor 0.5)
    it("withdrawal + tokenPriceAdjustForPerformance", () => {});
  });

  describe("Aave aERC20", () => {
    // Create Fund, no management fee, enable usdc, aaveLending Pool
    // Deposit $1 conventional way
    // Check tokenPriceAdjustForPerformance() should be $1
    // Check hasDirectDeposit() == FALSE
    // Deposit aUSDC $1 directly
    // Check hasDirectDeposit() == TRUE
    // Check TokenPrice() should be $2
    // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor 0.5)
    // Call recordDirectDepositValue
    // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor 0.5)
    // Deposit $1 conventional way
    // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor 0.5)
    it("tokenPriceAdjustForPerformance", () => {});
  });
});
