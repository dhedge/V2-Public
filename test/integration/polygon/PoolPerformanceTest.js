const { ethers, upgrades } = require("hardhat");
const { expect, use } = require("chai");
const chaiAlmost = require("chai-almost");

use(chaiAlmost());

const units = (value) => ethers.utils.parseUnits(value.toString());

const sushiswapV2Router = "0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506";

// For mainnet
const wmatic = "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270";
const usdc = "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174";
const matic_price_feed = "0xAB594600376Ec9fD91F8e885dADF0CE036862dE0";
const usdc_price_feed = "0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7";

describe("PoolPerformance", function () {
  let USDC;
  let logicOwner, manager, dao;
  let PoolLogic;
  let poolFactory, poolLogicProxy, poolPerformanceProxy;

  beforeEach(async function () {
    [logicOwner, manager, dao, user] = await ethers.getSigners();

    const AssetHandlerLogic = await ethers.getContractFactory("AssetHandler");

    const Governance = await ethers.getContractFactory("Governance");
    let governance = await Governance.deploy();

    const PoolPerformance = await ethers.getContractFactory("PoolPerformance");
    const poolPerformance = await PoolPerformance.deploy();
    poolPerformanceProxy = await PoolPerformance.attach(poolPerformance.address);

    PoolLogic = await ethers.getContractFactory("PoolLogic");
    const poolLogic = await PoolLogic.deploy();

    const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
    const poolManagerLogic = await PoolManagerLogic.deploy();

    // Initialize Asset Price Consumer
    const assetWmatic = { asset: wmatic, assetType: 0, aggregator: matic_price_feed };
    const assetUsdc = { asset: usdc, assetType: 0, aggregator: usdc_price_feed };
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
      poolPerformance.address,
    ]);
    await poolFactory.deployed();

    const ERC20Guard = await ethers.getContractFactory("ERC20Guard");
    erc20Guard = await ERC20Guard.deploy();
    erc20Guard.deployed();

    await governance.setAssetGuard(0, erc20Guard.address);

    // Setup LogicOwner with some USDC
    const IWETH = await hre.artifacts.readArtifact("IWETH");
    const WMatic = await ethers.getContractAt(IWETH.abi, wmatic);
    const IERC20 = await hre.artifacts.readArtifact("IERC20");
    USDC = await ethers.getContractAt(IERC20.abi, usdc);

    const IUniswapV2Router = await hre.artifacts.readArtifact("IUniswapV2Router");
    const sushiswapRouter = await ethers.getContractAt(IUniswapV2Router.abi, sushiswapV2Router);
    await WMatic.deposit({ value: units(500) });

    await WMatic.approve(sushiswapV2Router, units(500));
    await sushiswapRouter.swapExactTokensForTokens(
      units(500),
      0,
      [wmatic, usdc],
      logicOwner.address,
      Math.floor(Date.now() / 1000 + 100000000),
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
    // Call recordDirectDepositValue  XXXXXXXXXXXXXX
    // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor 0.5)
    // Deposit $1 conventional way
    // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor 0.5)
    // it("tokenPriceAdjustedForPerformance", async () => {
    //   const managerFee = new ethers.BigNumber.from("0"); // 0%;
    //   // Create the fund we're going to use for testing
    //   await poolFactory.createFund(false, manager.address, "Barren Wuffet", "Test Fund", "DHTF", managerFee, [
    //     [usdc, true],
    //   ]);
    //   const funds = await poolFactory.getDeployedFunds();
    //   poolLogicProxy = await PoolLogic.attach(funds[0]);
    //   // Deposit $1 conventional way
    //   await USDC.approve(poolLogicProxy.address, (100e6).toString());
    //   await poolLogicProxy.deposit(usdc, (100e6).toString());
    //   // Check tokenPriceAdjustForPerformance() should be $1
    //   expect((await poolPerformanceProxy.tokenPrice(poolLogicProxy.address)).toString()).to.equal((1e18).toString());
    //   expect((await poolPerformanceProxy.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
    //     (1e18).toString(),
    //   );
    //   // Check hasDirectDeposit() == FALSE
    //   expect(await poolPerformanceProxy.hasDirectDeposit(poolLogicProxy.address)).to.equal(false);

    //   // Deposit $1 directly
    //   await USDC.transfer(poolLogicProxy.address, (100e6).toString());
    //   // expect((await poolPerformanceProxy.directDepositFactor2(poolLogicProxy.address)).toString()).to.equal(5e17);
    //   // Check TokenPrice() should be $2
    //   expect((await poolPerformanceProxy.tokenPrice(poolLogicProxy.address)).toString()).to.equal((2e18).toString());
    //   // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor 0.5)
    //   expect((await poolPerformanceProxy.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
    //     (1e18).toString(),
    //   );

    //   // Call recordDirectDepositValue
    //   await poolPerformanceProxy.recordDirectDepositValue(poolLogicProxy.address);

    //   // Check TokenPrice() should be $2
    //   expect((await poolPerformanceProxy.tokenPrice(poolLogicProxy.address)).toString()).to.equal((2e18).toString());
    //   // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor 0.5)
    //   expect((await poolPerformanceProxy.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
    //     (1e18).toString(),
    //   );

    //   // Deposit $1 conventional way
    //   await USDC.approve(poolLogicProxy.address, (100e6).toString());
    //   await poolLogicProxy.deposit(usdc, (100e6).toString());

    //   // Check TokenPrice() should be $2
    //   expect((await poolPerformanceProxy.tokenPrice(poolLogicProxy.address)).toString()).to.equal((2e18).toString());
    //   // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor 0.5)
    //   expect((await poolPerformanceProxy.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
    //     (1e18).toString(),
    //   );
    // });

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

    // In this test we test that the fee + performance is calculated correctly
    // Create Fund, with 20% management fee, enable usdc
    // Deposit $1 conventional way
    // Check tokenPriceAdjustedForPerformanceAndManagerFee() should be $1
    // Check hasDirectDeposit() == FALSE
    // Deposit $1 directly
    // Check hasDirectDeposit() == TRUE
    // Check TokenPrice() should be $2
    // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor 0.5)
    // Check tokenPriceAdjustedForPerformanceAndManagerFee == $2 - 50c = $1.50 / 0.5 = 0.75; (i.e directDepositFactor 0.5)
    // Call recordDirectDepositValue
    // Check tokenPriceAdjustedForPerformanceAndManagerFee == $2 - .04 / 2 = $0.8; (i.e directDepositFactor 0.5)
    // Deposit $1 conventional way
    // Check tokenPriceAdjustedForPerformanceAndManagerFee == $2 - .04 / 2 = $0.8; (i.e directDepositFactor 0.5)
    it("tokenPriceAdjustedForPerformanceAndManagerFee", async () => {
      const managerFee = new ethers.BigNumber.from("5000"); // 50%;
      await poolFactory.createFund(false, manager.address, "Barren Wuffet", "Test Fund", "DHTF", managerFee, [
        [usdc, true],
      ]);
      const funds = await poolFactory.getDeployedFunds();
      const fund = funds[0];
      poolLogicProxy = await PoolLogic.attach(fund);

      // Deposit $1 conventional way
      await USDC.approve(poolLogicProxy.address, (100e6).toString());
      await poolLogicProxy.deposit(usdc, (100e6).toString());

      console.log((await poolPerformanceProxy.fee(poolLogicProxy.address)).toString());

      // Check tokenPriceAdjustForPerformance() should be $1
      expect((await poolPerformanceProxy.tokenPrice(poolLogicProxy.address)).toString()).to.equal((1e18).toString());
      expect((await poolPerformanceProxy.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        (1e18).toString(),
      );
      expect((await poolPerformanceProxy.tokenPriceAdjustedForManagerFee(poolLogicProxy.address)).toString()).to.equal(
        (1e18).toString(),
      );
      expect(
        (await poolPerformanceProxy.tokenPriceAdjustedForPerformanceAndManagerFee(poolLogicProxy.address)).toString(),
      ).to.equal((1e18).toString());
      // Check hasDirectDeposit() == FALSE
      expect(await poolPerformanceProxy.hasDirectDeposit(poolLogicProxy.address)).to.equal(false);

      // Deposit $1 directly
      await USDC.transfer(poolLogicProxy.address, (100e6).toString());

      console.log((await poolPerformanceProxy.fee(poolLogicProxy.address)).toString());

      // Check TokenPrice() should be $2
      expect((await poolPerformanceProxy.tokenPrice(poolLogicProxy.address)).toString()).to.equal((2e18).toString());
      // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor 0.5)
      expect((await poolPerformanceProxy.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        (1e18).toString(),
      );

      // Check to tokenPriceAdjustedForManagerFee fee should be $2 - 50c  = $1.50
      expect((await poolPerformanceProxy.tokenPriceAdjustedForManagerFee(poolLogicProxy.address)).toString()).to.equal(
        (15e17).toString(),
      );
      // TokenPrice = $2
      // Performance = $1
      // Fee = Performance * 50% = 0.50
      // directDepositFactor = 0.5
      // tokenPriceAdjustedForPerformanceAndManagerFee = tokenPrice - fee * directDepositFactor 0.5
      // Check tokenPriceAdjustedForPerformanceAndManagerFee == 0.75;
      expect(
        (await poolPerformanceProxy.tokenPriceAdjustedForPerformanceAndManagerFee(poolLogicProxy.address)).toString(),
      ).to.equal((75e16).toString());

      // Call recordDirectDepositValue
      await poolPerformanceProxy.recordDirectDepositValue(poolLogicProxy.address);

      // Check TokenPrice() should be $2
      expect((await poolPerformanceProxy.tokenPrice(poolLogicProxy.address)).toString()).to.equal((2e18).toString());
      // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor 0.5)
      expect((await poolPerformanceProxy.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        (1e18).toString(),
      );
      // Check to tokenPriceAdjustedForManagerFee fee should be $2 - 50c  = $1.50
      expect((await poolPerformanceProxy.tokenPriceAdjustedForManagerFee(poolLogicProxy.address)).toString()).to.equal(
        (15e17).toString(),
      );
      // TokenPrice = $2
      // Performance = $1
      // Fee = Performance * 50% = 0.50
      // directDepositFactor = 0.5
      // tokenPriceAdjustedForPerformanceAndManagerFee = tokenPrice - fee * directDepositFactor 0.5
      // Check tokenPriceAdjustedForPerformanceAndManagerFee == 0.75;
      expect(
        (await poolPerformanceProxy.tokenPriceAdjustedForPerformanceAndManagerFee(poolLogicProxy.address)).toString(),
      ).to.equal((75e16).toString());

      console.log((await poolLogicProxy.totalSupply()).toString());
      await poolLogicProxy.mintManagerFee();
      console.log((await poolLogicProxy.totalSupply()).toString());

      // Check TokenPrice() should be $2
      expect((await poolPerformanceProxy.tokenPrice(poolLogicProxy.address)).toString()).to.equal((2e18).toString());
      // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor 0.5)
      expect((await poolPerformanceProxy.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        (1e18).toString(),
      );
      // Check to tokenPriceAdjustedForManagerFee fee should be $2 - 50c  = $1.50
      expect((await poolPerformanceProxy.tokenPriceAdjustedForManagerFee(poolLogicProxy.address)).toString()).to.equal(
        (15e17).toString(),
      );
      // TokenPrice = $2
      // Performance = $1
      // Fee = Performance * 50% = 0.50
      // directDepositFactor = 0.5
      // tokenPriceAdjustedForPerformanceAndManagerFee = tokenPrice - fee * directDepositFactor 0.5
      // Check tokenPriceAdjustedForPerformanceAndManagerFee == 0.75;
      expect(
        (await poolPerformanceProxy.tokenPriceAdjustedForPerformanceAndManagerFee(poolLogicProxy.address)).toString(),
      ).to.equal((75e16).toString());

      // Deposit $1 conventional way
      await USDC.approve(poolLogicProxy.address, (100e6).toString());
      await poolLogicProxy.deposit(usdc, (100e6).toString());

      // The deposit first mints manager fee tokens in this case 0.25 tokens
      // Which means before the deposit there is 1.25 tokens and $2 value
      // i.e the tokenValue is $1.6
      // Check TokenPrice() should be $1.600.62
      expect((await poolPerformanceProxy.tokenPrice(poolLogicProxy.address)).toString()).to.equal((16e17).toString());
      // Check tokenPriceAdjustForPerformance == $0.80; (i.e directDepositFactor 0.5)
      expect((await poolPerformanceProxy.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        (8e17).toString(),
      );
      // Check to tokenPriceAdjustedForManagerFee == tokenPrice as fee was minted during deposit
      expect((await poolPerformanceProxy.tokenPriceAdjustedForManagerFee(poolLogicProxy.address)).toString()).to.equal(
        (16e17).toString(),
      );
      // Check to tokenPriceAdjustedForPerformanceAndManagerFee = tokenPriceAdjustedForPerformance as fee was minted during deposit
      expect(
        (await poolPerformanceProxy.tokenPriceAdjustedForPerformanceAndManagerFee(poolLogicProxy.address)).toString(),
      ).to.equal((8e17).toString());
    });
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
