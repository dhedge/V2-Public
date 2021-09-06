const { ethers, upgrades } = require("hardhat");
const { expect, use } = require("chai");
const { solidity } = require("ethereum-waffle");

const { BigNumber } = ethers;

use(solidity);

const units = (value) => ethers.utils.parseUnits(value.toString());

const sushiswapV2Router = "0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506";

// For mainnet
const wmatic = "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270";
const usdc = "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174";
const matic_price_feed = "0xAB594600376Ec9fD91F8e885dADF0CE036862dE0";
const usdc_price_feed = "0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7";

const oneDollar = 1e18;
const twoDollar = 2e18;

describe("PoolPerformance", function () {
  let USDC;
  let logicOwner, manager, dao;
  let PoolLogic;
  let poolFactory, poolLogicProxy, poolPerformanceProxy;

  beforeEach(async function () {
    [logicOwner, manager, dao] = await ethers.getSigners();

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

  describe("Only Standard ERC20 supportedAssets", () => {
    // Tests that tokenPriceAdjustedForPerformance adjusts for direct deposits
    // Create Fund, no management fee, enable usdc
    // Deposit $1 conventional way
    // Check tokenPriceAdjustForPerformance() should be $1
    // Check hasDirectDeposit() == FALSE
    // Deposit $1 directly
    // Check hasDirectDeposit() == TRUE
    // Check TokenPrice() should be $2
    // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor $1)
    // Call recordDirectDepositValue
    // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor $1)
    // Deposit $1 conventional way
    // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor $1)
    it("tokenPriceAdjustedForPerformance", async () => {
      const managerFee = new ethers.BigNumber.from("0"); // 0%;
      // Create the fund we're going to use for testing
      await poolFactory.createFund(false, manager.address, "Barren Wuffet", "Test Fund", "DHTF", managerFee, [
        [usdc, true],
      ]);
      const funds = await poolFactory.getDeployedFunds();
      poolLogicProxy = await PoolLogic.attach(funds[0]);
      // Deposit $1 conventional way
      await USDC.approve(poolLogicProxy.address, (100e6).toString());
      await poolLogicProxy.deposit(usdc, (100e6).toString());
      // Check tokenPriceAdjustForPerformance() should be $1
      expect((await poolPerformanceProxy.tokenPrice(poolLogicProxy.address)).toString()).to.equal(oneDollar.toString());
      expect((await poolPerformanceProxy.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );
      // Check hasDirectDeposit() == FALSE
      expect(await poolPerformanceProxy.hasDirectDeposit(poolLogicProxy.address)).to.equal(false);
      // Deposit $1 directly
      await USDC.transfer(poolLogicProxy.address, (100e6).toString());
      // Check TokenPrice() should be $2
      expect((await poolPerformanceProxy.tokenPrice(poolLogicProxy.address)).toString()).to.equal(twoDollar.toString());
      // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor $1)
      expect((await poolPerformanceProxy.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );
      // Call recordDirectDepositValue
      await poolPerformanceProxy.recordDirectDepositValue(poolLogicProxy.address);
      // Check TokenPrice() should be $2
      expect((await poolPerformanceProxy.tokenPrice(poolLogicProxy.address)).toString()).to.equal(twoDollar.toString());
      // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor $1)
      expect((await poolPerformanceProxy.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );
      // Deposit $1 conventional way
      await USDC.approve(poolLogicProxy.address, (100e6).toString());
      await poolLogicProxy.deposit(usdc, (100e6).toString());
      // Check TokenPrice() should be $2
      expect((await poolPerformanceProxy.tokenPrice(poolLogicProxy.address)).toString()).to.equal(twoDollar.toString());
      // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor $1)
      expect((await poolPerformanceProxy.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );
    });

    // In this test we make sure users can withdraw without disrupting the directDeposit detection
    // Create Fund, no management fee, enable usdc
    // Deposit $1 conventional way
    // Check tokenPriceAdjustForPerformance() should be $1
    // Check hasDirectDeposit() == FALSE
    // Deposit $1 directly
    // Deposit $1 conventional way
    // Check Price
    // Deposit $1 conventional way
    // Check Price
    // Withdraw
    // Check Price
    it("withdrawal + tokenPriceAdjustForPerformance", async () => {
      const managerFee = new ethers.BigNumber.from("0"); // 0%;
      // Create the fund we're going to use for testing
      await poolFactory.createFund(false, manager.address, "Barren Wuffet", "Test Fund", "DHTF", managerFee, [
        [usdc, true],
      ]);
      const funds = await poolFactory.getDeployedFunds();
      poolLogicProxy = await PoolLogic.attach(funds[0]);
      // Deposit $1 conventional way
      await USDC.approve(poolLogicProxy.address, (100e6).toString());
      await poolLogicProxy.deposit(usdc, (100e6).toString());
      // Deposit $1 directly
      await USDC.transfer(poolLogicProxy.address, (100e6).toString());

      // Deposit $1 conventional way
      // This will record the direct deposit factor
      await USDC.approve(poolLogicProxy.address, (100e6).toString());
      await poolLogicProxy.deposit(usdc, (100e6).toString());

      // Check token price is $2
      expect((await poolPerformanceProxy.tokenPrice(poolLogicProxy.address)).toString()).to.equal(twoDollar.toString());
      // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor $1)
      expect((await poolPerformanceProxy.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );

      await poolFactory.setExitCooldown(0);
      const withdrawQuarterAmount = (await poolLogicProxy.totalSupply()) / 4;
      await poolLogicProxy.withdraw(withdrawQuarterAmount.toString());

      // Check token price is still $2
      expect((await poolPerformanceProxy.tokenPrice(poolLogicProxy.address)).toString()).to.equal(twoDollar.toString());
      // Check tokenPriceAdjustForPerformance is still == $1; (i.e directDepositFactor $1)
      expect((await poolPerformanceProxy.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );
    });

    // In this test we test that the realtime fee + performance is calculated correctly
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
      // Check tokenPriceAdjustForPerformance() should be $1
      expect((await poolPerformanceProxy.tokenPrice(poolLogicProxy.address)).toString()).to.equal(oneDollar.toString());
      expect((await poolPerformanceProxy.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );
      expect((await poolPerformanceProxy.tokenPriceAdjustedForManagerFee(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );
      expect(
        (await poolPerformanceProxy.tokenPriceAdjustedForPerformanceAndManagerFee(poolLogicProxy.address)).toString(),
      ).to.equal(oneDollar.toString());
      // Check hasDirectDeposit() == FALSE
      expect(await poolPerformanceProxy.hasDirectDeposit(poolLogicProxy.address)).to.equal(false);
      // DollarSixty
      // You might be thinking you expect this to be $1.50 not $1.60 but..
      // we mint the manager fee in a novel way, that's not exactly performance fee.
      // The mints manager fee mints 0.25 tokens (a value of 50% of the current performance value)
      // Which means before the mint there is 1 token and after mint there is 1.25 tokens and $2 value
      // i.e the tokenValue is $1.6 now because there is more tokens in circulation
      // Check TokenPrice() should be $1.60
      const expectedTokenPriceAdjustedForManagerFee = 16e17;
      const checkTokenValue = async () => {
        expect(
          (await poolPerformanceProxy.tokenPriceAdjustedForManagerFee(poolLogicProxy.address)).toString(),
        ).to.equal(expectedTokenPriceAdjustedForManagerFee.toString());
        expect(
          (await poolPerformanceProxy.tokenPriceAdjustedForPerformanceAndManagerFee(poolLogicProxy.address)).toString(),
          // sixty cents
        ).to.equal((expectedTokenPriceAdjustedForManagerFee - 1e18).toString());
      };
      // Deposit $1 directly
      await USDC.transfer(poolLogicProxy.address, (100e6).toString());
      // The direct deposit should be detected.
      expect((await poolPerformanceProxy.tokenPrice(poolLogicProxy.address)).toString()).to.equal(twoDollar.toString());
      await checkTokenValue();
      // Call recordDirectDepositValue
      await poolPerformanceProxy.recordDirectDepositValue(poolLogicProxy.address);
      // This should have no affect on tokenPricesAdjustedForFee
      await checkTokenValue();
      // We mint the manager fee
      await poolLogicProxy.mintManagerFee();
      // The base tokenPrice should now be the same as the tokenPriceAdjustedForManagerFees now fees are minted
      expect((await poolPerformanceProxy.tokenPrice(poolLogicProxy.address)).toString()).to.equal(
        (await poolPerformanceProxy.tokenPriceAdjustedForManagerFee(poolLogicProxy.address)).toString(),
      );
      // The tokenPriceAdjustedForPerformance should now be the same as adjustedForPerformanceAndManagerFee now fees are minted
      expect((await poolPerformanceProxy.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        (await poolPerformanceProxy.tokenPriceAdjustedForPerformanceAndManagerFee(poolLogicProxy.address)).toString(),
      );
      // This should have no affect on tokenPricesAdjustedForFee
      await checkTokenValue();
      // Deposit $1 conventional way
      await USDC.approve(poolLogicProxy.address, (100e6).toString());
      await poolLogicProxy.deposit(usdc, (100e6).toString());
      // This should have no affect on tokenPricesAdjustedForFee
      checkTokenValue();
    });

    it("tokenPriceAdjustedForPerformanceAndManagerFee with small manager fee, small deposit", async () => {
      const oneDollarTwentyCents = 12e17;
      const managerFee = new ethers.BigNumber.from("1000"); // 10%;
      await poolFactory.createFund(false, manager.address, "Barren Wuffet", "Test Fund", "DHTF", managerFee, [
        [usdc, true],
      ]);
      const funds = await poolFactory.getDeployedFunds();
      const fund = funds[0];
      poolLogicProxy = await PoolLogic.attach(fund);
      // Deposit $10 conventional way
      await USDC.approve(poolLogicProxy.address, (1000e6).toString());
      await poolLogicProxy.deposit(usdc, (1000e6).toString());
      // Check tokenPriceAdjustForPerformance() should be $1
      expect((await poolPerformanceProxy.tokenPrice(poolLogicProxy.address)).toString()).to.equal(oneDollar.toString());
      expect((await poolPerformanceProxy.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );
      expect((await poolPerformanceProxy.tokenPriceAdjustedForManagerFee(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );
      expect(
        (await poolPerformanceProxy.tokenPriceAdjustedForPerformanceAndManagerFee(poolLogicProxy.address)).toString(),
      ).to.equal(oneDollar.toString());
      // Check hasDirectDeposit() == FALSE
      expect(await poolPerformanceProxy.hasDirectDeposit(poolLogicProxy.address)).to.equal(false);

      // Deposit $2 directly
      // This means the fee should be around
      await USDC.transfer(poolLogicProxy.address, (200e6).toString());

      // We have $10 in the pool
      // Direct deposit $2
      // now every token is worth $1.2
      // The manager gets ~10% of the 0.2 - around 2 cents
      // The direct deposit factor is 20c (per token)
      // tokenPriceWithFee 118
      // tokenPriceWithFeeAndPerformance 118-20c == 98c;
      expect((await poolPerformanceProxy.tokenPrice(poolLogicProxy.address)).toString()).to.equal(
        oneDollarTwentyCents.toString(),
      );

      // We have 10 in the pool
      // Direct deposit $2
      const checkTokenValue = async () => {
        console.log(">>>>>>>>>>", (await poolPerformanceProxy.fee(poolLogicProxy.address)).toString());
        expect(await poolPerformanceProxy.tokenPriceAdjustedForManagerFee(poolLogicProxy.address)).to.equal(
          // dollar18Cents
          "1180327868852459016",
        );

        expect(
          (await poolPerformanceProxy.tokenPriceAdjustedForPerformanceAndManagerFee(poolLogicProxy.address)).toString(),
          // ninetyEightCents
        ).to.equal("980327868852459016");
      };

      await checkTokenValue();

      // We mint the manager fee
      await poolLogicProxy.mintManagerFee();

      // The base tokenPrice should now be the same as the tokenPriceAdjustedForManagerFees now fees are minted
      expect((await poolPerformanceProxy.tokenPrice(poolLogicProxy.address)).toString()).to.equal(
        (await poolPerformanceProxy.tokenPriceAdjustedForManagerFee(poolLogicProxy.address)).toString(),
      );
      // The tokenPriceAdjustedForPerformance should now be the same as adjustedForPerformanceAndManagerFee now fees are minted
      expect((await poolPerformanceProxy.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        (await poolPerformanceProxy.tokenPriceAdjustedForPerformanceAndManagerFee(poolLogicProxy.address)).toString(),
      );
      // This should have no affect on tokenPricesAdjustedForFee
      await checkTokenValue();
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
    // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor $1)
    // Call recordDirectDepositValue
    // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor $1)
    // Deposit $1 conventional way
    // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor $1)
    it("tokenPriceAdjustForPerformance", () => {});
  });
});
