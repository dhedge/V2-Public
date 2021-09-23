const { ethers, upgrades } = require("hardhat");
const { expect, use } = require("chai");
const { solidity } = require("ethereum-waffle");
const { checkAlmostSame, toBytes32, units } = require("../../TestHelpers");
const { sushi, aave, assets, price_feeds } = require("../polygon-data");

use(solidity);

const oneDollar = 1e18;
const twoDollar = 2e18;

describe("PoolPerformance", function () {
  let USDC, WETH;
  let logicOwner, manager, dao;
  let PoolLogic;
  let assetHandler, governance, poolFactory, poolLogicProxy, poolPerformance;

  beforeEach(async function () {
    [logicOwner, manager, dao] = await ethers.getSigners();

    const AssetHandlerLogic = await ethers.getContractFactory("AssetHandler");

    const Governance = await ethers.getContractFactory("Governance");
    governance = await Governance.deploy();

    const PoolPerformance = await ethers.getContractFactory("PoolPerformance");
    poolPerformance = await upgrades.deployProxy(PoolPerformance, [aave.protocolDataProvider]);
    await poolPerformance.deployed();

    PoolLogic = await ethers.getContractFactory("PoolLogic");
    const poolLogic = await PoolLogic.deploy();

    const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
    const poolManagerLogic = await PoolManagerLogic.deploy();

    // Initialize Asset Price Consumer
    const assetWmatic = { asset: assets.wmatic, assetType: 0, aggregator: price_feeds.matic };
    const assetWeth = { asset: assets.weth, assetType: 0, aggregator: price_feeds.eth };
    const assetUsdc = { asset: assets.usdc, assetType: 0, aggregator: price_feeds.usdc };
    const assetHandlerInitAssets = [assetWmatic, assetUsdc, assetWeth];

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
    ]);
    await poolFactory.deployed();

    await poolFactory.setPoolPerformanceAddress(poolPerformance.address);

    const ERC20Guard = await ethers.getContractFactory("ERC20Guard");
    erc20Guard = await ERC20Guard.deploy();
    erc20Guard.deployed();

    await governance.setAssetGuard(0, erc20Guard.address);

    // Setup LogicOwner with some USDC
    const IWETH = await hre.artifacts.readArtifact("IWETH");
    const WMatic = await ethers.getContractAt(IWETH.abi, assets.wmatic);
    const IERC20 = await hre.artifacts.readArtifact("IERC20");
    USDC = await ethers.getContractAt(IERC20.abi, assets.usdc);
    WETH = await ethers.getContractAt(IERC20.abi, assets.weth);

    const IUniswapV2Router = await hre.artifacts.readArtifact("IUniswapV2Router");
    const sushiswapRouter = await ethers.getContractAt(IUniswapV2Router.abi, sushi.router);
    await WMatic.deposit({ value: units(1000) });

    // Get USDC
    await WMatic.approve(sushi.router, units(1000));
    await sushiswapRouter.swapExactTokensForTokens(
      units(500),
      0,
      [assets.wmatic, assets.usdc],
      logicOwner.address,
      Math.floor(Date.now() / 1000 + 100000000),
    );

    // Get Weth for AAVE Tests
    await sushiswapRouter.swapExactTokensForTokens(
      units(500),
      0,
      [assets.wmatic, assets.weth],
      logicOwner.address,
      Math.floor(Date.now() / 1000 + 100000000),
    );
  });

  describe("Only Standard ERC20 supportedAssets", () => {
    // Tests that tokenPriceAdjustedForPerformance adjusts for direct deposits
    // Create Fund, no management fee, enable usdc
    // Deposit $1 conventional way
    // Check tokenPriceAdjustForPerformance() should be $1
    // Check hasExternalBalances() == FALSE
    // Deposit $1 directly
    // Check hasExternalBalances() == TRUE
    // Check TokenPrice() should be $2
    // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor $1)
    // Call recordExternalValue
    // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor $1)
    // Deposit $1 conventional way
    // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor $1)
    it("tokenPriceAdjustedForPerformance", async () => {
      const managerFee = new ethers.BigNumber.from("0"); // 0%;
      // Create the fund we're going to use for testing
      await poolFactory.createFund(false, manager.address, "Barren Wuffet", "Test Fund", "DHTF", managerFee, [
        [assets.usdc, true],
      ]);
      const funds = await poolFactory.getDeployedFunds();
      poolLogicProxy = await PoolLogic.attach(funds[0]);
      // Deposit $1 conventional way
      await USDC.approve(poolLogicProxy.address, (100e6).toString());
      await poolLogicProxy.deposit(assets.usdc, (100e6).toString());
      // Check tokenPriceAdjustForPerformance() should be $1
      expect((await poolPerformance.tokenPrice(poolLogicProxy.address)).toString()).to.equal(oneDollar.toString());
      expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );
      // Check hasExternalBalances() == FALSE
      expect(await poolPerformance.hasExternalBalances(poolLogicProxy.address)).to.equal(false);
      // Deposit $1 directly
      await USDC.transfer(poolLogicProxy.address, (100e6).toString());
      // Check TokenPrice() should be $2
      expect((await poolPerformance.tokenPrice(poolLogicProxy.address)).toString()).to.equal(twoDollar.toString());
      // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor $1)
      expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );
      // Call recordExternalValue
      await poolPerformance.recordExternalValue(poolLogicProxy.address);
      // Check TokenPrice() should be $2
      expect((await poolPerformance.tokenPrice(poolLogicProxy.address)).toString()).to.equal(twoDollar.toString());
      // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor $1)
      expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );
      // Deposit $1 conventional way
      await USDC.approve(poolLogicProxy.address, (100e6).toString());
      await poolLogicProxy.deposit(assets.usdc, (100e6).toString());
      // Check TokenPrice() should be $2
      expect((await poolPerformance.tokenPrice(poolLogicProxy.address)).toString()).to.equal(twoDollar.toString());
      // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor $1)
      expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );
    });

    // In this test we make sure users can withdraw without disrupting the directDeposit detection
    // Create Fund, no management fee, enable usdc
    // Deposit $1 conventional way
    // Check tokenPriceAdjustForPerformance() should be $1
    // Check hasExternalBalances() == FALSE
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
        [assets.usdc, true],
      ]);
      const funds = await poolFactory.getDeployedFunds();
      poolLogicProxy = await PoolLogic.attach(funds[0]);
      // Deposit $1 conventional way
      await USDC.approve(poolLogicProxy.address, (100e6).toString());
      await poolLogicProxy.deposit(assets.usdc, (100e6).toString());
      // Deposit $1 directly
      await USDC.transfer(poolLogicProxy.address, (100e6).toString());

      // Deposit $1 conventional way
      // This will record the direct deposit factor
      await USDC.approve(poolLogicProxy.address, (100e6).toString());
      await poolLogicProxy.deposit(assets.usdc, (100e6).toString());

      // Check token price is $2
      expect((await poolPerformance.tokenPrice(poolLogicProxy.address)).toString()).to.equal(twoDollar.toString());
      // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor $1)
      expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );

      await poolFactory.setExitCooldown(0);
      const withdrawQuarterAmount = (await poolLogicProxy.totalSupply()) / 4;
      await poolLogicProxy.withdraw(withdrawQuarterAmount.toString());

      // Check token price is still $2
      expect((await poolPerformance.tokenPrice(poolLogicProxy.address)).toString()).to.equal(twoDollar.toString());
      // Check tokenPriceAdjustForPerformance is still == $1; (i.e directDepositFactor $1)
      expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );
    });

    // In this test we test that the realtime fee + performance is calculated correctly
    it("tokenPriceAdjustedForPerformanceAndManagerFee", async () => {
      const managerFee = new ethers.BigNumber.from("5000"); // 50%;
      await poolFactory.createFund(false, manager.address, "Barren Wuffet", "Test Fund", "DHTF", managerFee, [
        [assets.usdc, true],
      ]);
      const funds = await poolFactory.getDeployedFunds();
      const fund = funds[0];
      poolLogicProxy = await PoolLogic.attach(fund);
      // Deposit $1 conventional way
      await USDC.approve(poolLogicProxy.address, (100e6).toString());
      await poolLogicProxy.deposit(assets.usdc, (100e6).toString());
      // Check tokenPriceAdjustForPerformance() should be $1
      expect((await poolPerformance.tokenPrice(poolLogicProxy.address)).toString()).to.equal(oneDollar.toString());
      expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );
      expect((await poolPerformance.tokenPriceAdjustedForManagerFee(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );
      expect(
        (await poolPerformance.tokenPriceAdjustedForPerformanceAndManagerFee(poolLogicProxy.address)).toString(),
      ).to.equal(oneDollar.toString());
      // Check hasExternalBalances() == FALSE
      expect(await poolPerformance.hasExternalBalances(poolLogicProxy.address)).to.equal(false);
      // DollarSixty
      // You might be thinking you expect this to be $1.50 not $1.60 because
      // There is $1 of performance and 50% performance fee and so manager fee should be worth 50c but
      // we mint the manager fee in a novel way, that's not exactly performance fee.
      // The mints manager fee mints 0.25 tokens (a value of 50% of the current performance value)
      // Which means before the mint there is 1 token and after mint there is 1.25 tokens and $2 value
      // i.e the tokenValue is $1.6 now because there is more tokens in circulation
      // Check TokenPrice() should be $1.60
      const expectedTokenPriceAdjustedForManagerFee = 16e17;
      const checkTokenValue = async () => {
        expect((await poolPerformance.tokenPriceAdjustedForManagerFee(poolLogicProxy.address)).toString()).to.equal(
          expectedTokenPriceAdjustedForManagerFee.toString(),
        );
        expect(
          (await poolPerformance.tokenPriceAdjustedForPerformanceAndManagerFee(poolLogicProxy.address)).toString(),
          // sixty cents
        ).to.equal((expectedTokenPriceAdjustedForManagerFee / 2).toString());
      };
      // Deposit $1 directly
      await USDC.transfer(poolLogicProxy.address, (100e6).toString());
      // The direct deposit should be detected.
      expect((await poolPerformance.tokenPrice(poolLogicProxy.address)).toString()).to.equal(twoDollar.toString());
      await checkTokenValue();
      // Call recordExternalValue
      await poolPerformance.recordExternalValue(poolLogicProxy.address);
      // This should have no affect on tokenPricesAdjustedForFee
      await checkTokenValue();
      // We mint the manager fee
      await poolLogicProxy.mintManagerFee();
      // The base tokenPrice should now be the same as the tokenPriceAdjustedForManagerFees now fees are minted
      expect((await poolPerformance.tokenPrice(poolLogicProxy.address)).toString()).to.equal(
        (await poolPerformance.tokenPriceAdjustedForManagerFee(poolLogicProxy.address)).toString(),
      );
      // The tokenPriceAdjustedForPerformance should now be the same as adjustedForPerformanceAndManagerFee now fees are minted
      expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        (await poolPerformance.tokenPriceAdjustedForPerformanceAndManagerFee(poolLogicProxy.address)).toString(),
      );
      // This should have no affect on tokenPricesAdjustedForFee
      await checkTokenValue();
      // Deposit $1 conventional way
      await USDC.approve(poolLogicProxy.address, (100e6).toString());
      await poolLogicProxy.deposit(assets.usdc, (100e6).toString());
      // This should have no affect on tokenPricesAdjustedForFee
      checkTokenValue();
    });

    it("tokenPriceAdjustedForPerformanceAndManagerFee with small manager fee, small deposit", async () => {
      const oneDollarTwentyCents = 12e17;
      const managerFee = new ethers.BigNumber.from("1000"); // 10%;
      await poolFactory.createFund(false, manager.address, "Barren Wuffet", "Test Fund", "DHTF", managerFee, [
        [assets.usdc, true],
      ]);
      const funds = await poolFactory.getDeployedFunds();
      const fund = funds[0];
      poolLogicProxy = await PoolLogic.attach(fund);
      // Deposit $10 conventional way
      await USDC.approve(poolLogicProxy.address, (1000e6).toString());
      await poolLogicProxy.deposit(assets.usdc, (1000e6).toString());
      // Check tokenPriceAdjustForPerformance() should be $1
      expect((await poolPerformance.tokenPrice(poolLogicProxy.address)).toString()).to.equal(oneDollar.toString());
      expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );
      expect((await poolPerformance.tokenPriceAdjustedForManagerFee(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );
      expect(
        (await poolPerformance.tokenPriceAdjustedForPerformanceAndManagerFee(poolLogicProxy.address)).toString(),
      ).to.equal(oneDollar.toString());
      // Check hasExternalBalances() == FALSE
      expect(await poolPerformance.hasExternalBalances(poolLogicProxy.address)).to.equal(false);

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
      expect((await poolPerformance.tokenPrice(poolLogicProxy.address)).toString()).to.equal(
        oneDollarTwentyCents.toString(),
      );

      // We have 10 in the pool
      // Direct deposit $2
      const checkTokenValue = async () => {
        expect(await poolPerformance.tokenPriceAdjustedForManagerFee(poolLogicProxy.address)).to.equal(
          // dollar18Cents
          "1180327868852459016",
        );

        expect(
          (await poolPerformance.tokenPriceAdjustedForPerformanceAndManagerFee(poolLogicProxy.address)).toString(),
          // dollar18Cents subtract 20c
          // nintetyEight cents
        ).to.equal("983606557377049179");
      };

      await checkTokenValue();

      // We mint the manager fee
      await poolLogicProxy.mintManagerFee();

      // The base tokenPrice should now be the same as the tokenPriceAdjustedForManagerFees now fees are minted
      expect((await poolPerformance.tokenPrice(poolLogicProxy.address)).toString()).to.equal(
        (await poolPerformance.tokenPriceAdjustedForManagerFee(poolLogicProxy.address)).toString(),
      );
      // The tokenPriceAdjustedForPerformance should now be the same as adjustedForPerformanceAndManagerFee now fees are minted
      expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        (await poolPerformance.tokenPriceAdjustedForPerformanceAndManagerFee(poolLogicProxy.address)).toString(),
      );
      // This should have no affect on tokenPricesAdjustedForFee
      await checkTokenValue();
    });
  });

  describe("Aave aERC20", () => {
    // Create Fund, no management fee, enable usdc + aaveLending Pool
    // Deposit $1 conventional way
    // Check tokenPriceAdjustForPerformance() should be $1
    // Check hasExternalBalances() == FALSE
    // Deposit aUSDC $1 directly
    // Check hasExternalBalances() == TRUE
    // Check TokenPrice() should be $2
    // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor $1)
    // Call recordExternalValue
    // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor $1)
    // Deposit $1 conventional way

    let AMUSDC, AMWETH, iERC20;
    beforeEach(async function () {
      const USDPriceAggregator = await ethers.getContractFactory("USDPriceAggregator");
      const usdPriceAggregator = await USDPriceAggregator.deploy();
      const assetLendingPool = { asset: aave.lendingPool, assetType: 3, aggregator: usdPriceAggregator.address };

      const IERC20 = await hre.artifacts.readArtifact("IERC20");
      iERC20 = new ethers.utils.Interface(IERC20.abi);

      const IAToken = await hre.artifacts.readArtifact("IAToken");

      AMUSDC = await ethers.getContractAt(IAToken.abi, aave.aTokens.usdc);
      AMWETH = await ethers.getContractAt(IAToken.abi, aave.aTokens.weth);

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

      await governance.setAssetGuard(3, aaveLendingPoolAssetGuard.address);
      await governance.setAssetGuard(4, lendingEnabledAssetGuard.address);
      await governance.setContractGuard(aave.lendingPool, aaveLendingPoolGuard.address);
      await governance.setContractGuard(aave.incentivesController, aaveIncentivesControllerGuard.address);

      const OpenAssetGuard = await ethers.getContractFactory("OpenAssetGuard");
      const openAssetGuard = await OpenAssetGuard.deploy([]);
      await openAssetGuard.deployed();

      await governance.setAddresses([
        // [toBytes32("swapRouter"), sushi.router],
        [toBytes32("aaveProtocolDataProvider"), aave.protocolDataProvider],
        [toBytes32("openAssetGuard"), openAssetGuard.address],
      ]);
      await assetHandler.addAssets([assetLendingPool]);
    });

    // In this test we simply check that depositing into aave doesn't affect our PoolPerf figures
    // Create the fund we're going to use for testing
    // Deposit $1 conventional way
    // Check tokenPriceAdjustForPerformance() should be $1
    // Approve usdc transfer to AAVE
    // Check before balances of usdc and amusdc
    // Deposit usdc to aave
    // Check after balances of usdc and amusdc
    // Check PoolPerformance Figures remain the same
    it("tokenPriceAdjustForPerformance no direct deposit", async () => {
      const usdcAmount = (100e6).toString();
      const managerFee = new ethers.BigNumber.from("0"); // 0%;
      // Create the fund we're going to use for testing
      await poolFactory.createFund(false, manager.address, "Barren Wuffet", "Test Fund", "DHTF", managerFee, [
        [assets.usdc, true],
        [aave.lendingPool, false],
      ]);
      const funds = await poolFactory.getDeployedFunds();
      poolLogicProxy = await PoolLogic.attach(funds[0]);
      // Deposit $1 conventional way
      await USDC.approve(poolLogicProxy.address, usdcAmount);
      await poolLogicProxy.deposit(assets.usdc, usdcAmount);

      // Check tokenPriceAdjustForPerformance() should be $1
      expect((await poolPerformance.tokenPrice(poolLogicProxy.address)).toString()).to.equal(oneDollar.toString());
      expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );

      const ILendingPool = await hre.artifacts.readArtifact("ILendingPool");
      const iLendingPool = new ethers.utils.Interface(ILendingPool.abi);

      // approve usdc
      let approveABI = iERC20.encodeFunctionData("approve", [aave.lendingPool, usdcAmount]);
      await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);

      const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
      const amusdcBalanceBefore = await AMUSDC.balanceOf(poolLogicProxy.address);

      expect(usdcBalanceBefore).to.be.equal(usdcAmount);
      expect(amusdcBalanceBefore).to.be.equal(0);

      expect((await poolPerformance.tokenPrice(poolLogicProxy.address)).toString()).to.equal(oneDollar.toString());

      // deposit
      let depositABI = iLendingPool.encodeFunctionData("deposit", [assets.usdc, usdcAmount, poolLogicProxy.address, 0]);
      await poolLogicProxy.connect(manager).execTransaction(aave.lendingPool, depositABI);

      const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
      const amusdcBalanceAfter = await AMUSDC.balanceOf(poolLogicProxy.address);
      expect(usdcBalanceAfter).to.be.equal((0).toString());
      checkAlmostSame(amusdcBalanceAfter, 100e6);

      // We check that depositing into AAVE doesn't affect any of our poolPerformance figures
      expect((await poolPerformance.tokenPrice(poolLogicProxy.address)).toString()).to.equal(oneDollar.toString());
      expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );
      expect((await poolPerformance.tokenPriceAdjustedForManagerFee(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );
      expect(
        (await poolPerformance.tokenPriceAdjustedForPerformanceAndManagerFee(poolLogicProxy.address)).toString(),
      ).to.equal(oneDollar.toString());
    });

    // In this test we make sure directDeposits of aTokens are accounted for by PoolPerformance
    // Create the fund we're going to use for testing
    // Deposit $1 conventional way
    // Check tokenPriceAdjustForPerformance() should be $1
    // Approve usdc transfer to AAVE
    // Check before balances of usdc and amusdc
    // Deposit usdc to aave
    // Check after balances of usdc and amusdc
    // Direct deposit amUSDC to Pool
    // check that the directDeposit of amUSDC is accounted for by PoolPerformance
    it("tokenPriceAdjustForPerformance with direct deposit", async () => {
      const usdcAmount = (100e6).toString();
      const managerFee = new ethers.BigNumber.from("0"); // 0%;
      // Create the fund we're going to use for testing
      await poolFactory.createFund(false, manager.address, "Barren Wuffet", "Test Fund", "DHTF", managerFee, [
        [assets.usdc, true],
        [aave.lendingPool, false],
      ]);
      const funds = await poolFactory.getDeployedFunds();
      poolLogicProxy = await PoolLogic.attach(funds[0]);
      // Deposit $1 conventional way
      await USDC.approve(poolLogicProxy.address, usdcAmount);
      await poolLogicProxy.deposit(assets.usdc, usdcAmount);

      // Check tokenPriceAdjustForPerformance() should be $1
      expect((await poolPerformance.tokenPrice(poolLogicProxy.address)).toString()).to.equal(oneDollar.toString());
      expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );

      const ILendingPool = await hre.artifacts.readArtifact("ILendingPool");
      const iLendingPool = new ethers.utils.Interface(ILendingPool.abi);

      // approve usdc
      let approveABI = iERC20.encodeFunctionData("approve", [aave.lendingPool, usdcAmount]);
      await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);

      const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
      const amusdcBalanceBefore = await AMUSDC.balanceOf(poolLogicProxy.address);

      expect(usdcBalanceBefore).to.be.equal(usdcAmount);
      expect(amusdcBalanceBefore).to.be.equal(0);

      expect((await poolPerformance.tokenPrice(poolLogicProxy.address)).toString()).to.equal(oneDollar.toString());

      // deposit
      let depositABI = iLendingPool.encodeFunctionData("deposit", [assets.usdc, usdcAmount, poolLogicProxy.address, 0]);
      await poolLogicProxy.connect(manager).execTransaction(aave.lendingPool, depositABI);

      expect(await USDC.balanceOf(poolLogicProxy.address)).to.be.equal((0).toString());
      checkAlmostSame(await AMUSDC.balanceOf(poolLogicProxy.address), 100e6);

      // Here we are taking some of the logicOwners usdc and depositing it directly into the aave Pool as amUSDC
      await USDC.approve(aave.lendingPool, usdcAmount);
      const AaveLendingPool = await ethers.getContractAt(ILendingPool.abi, aave.lendingPool);
      await AaveLendingPool.deposit(assets.usdc, usdcAmount, poolLogicProxy.address, 0);

      checkAlmostSame(await AMUSDC.balanceOf(poolLogicProxy.address), 200e6);

      // We check that the directDeposit of amUSDC is accounted for by PoolPerformance
      // We use closeTo here because every block we are getting crumbs as interest on our aAsset which
      // increases the price slightly
      expect((await poolPerformance.tokenPrice(poolLogicProxy.address)).toString()).closeTo(
        ethers.BigNumber.from(BigInt(twoDollar)),
        1e10,
      );
      expect((await poolPerformance.tokenPriceAdjustedForManagerFee(poolLogicProxy.address)).toString()).closeTo(
        ethers.BigNumber.from(BigInt(twoDollar)),
        1e10,
      );

      expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).closeTo(
        ethers.BigNumber.from(BigInt(twoDollar / 2)),
        1e10,
      );
      expect(
        (await poolPerformance.tokenPriceAdjustedForPerformanceAndManagerFee(poolLogicProxy.address)).toString(),
      ).closeTo(ethers.BigNumber.from(BigInt(twoDollar / 2)), 1e10);
    });

    // In this test we make sure directDeposits of aTokens are accounted for by PoolPerformance using WETH
    // Create the fund we're going to use for testing
    // Deposit x Weth conventional way
    // Check tokenPriceAdjustForPerformance() should be $1
    // Approve weth transfer to AAVE
    // Check before balances of weth and amweth
    // Deposit weth to aave
    // Check after balances of weth and amweth
    // Direct deposit amweth to Pool
    // check that the directDeposit of amWeth is accounted for by PoolPerformance
    it("tokenPriceAdjustForPerformance with direct deposit (WETH)", async () => {
      const managerFee = new ethers.BigNumber.from("0"); // 0%;
      // Create the fund we're going to use for testing
      await poolFactory.createFund(false, manager.address, "Barren Wuffet", "Test Fund", "DHTF", managerFee, [
        [assets.weth, true],
        [aave.lendingPool, false],
      ]);

      const balanceOfWeth = await WETH.balanceOf(logicOwner.address);
      const halfBalanceOfWeth = balanceOfWeth.div(2);

      const funds = await poolFactory.getDeployedFunds();
      poolLogicProxy = await PoolLogic.attach(funds[0]);
      // Deposit $1 conventional way
      await WETH.approve(poolLogicProxy.address, halfBalanceOfWeth);
      await poolLogicProxy.deposit(assets.weth, halfBalanceOfWeth);

      // Check tokenPriceAdjustForPerformance() should be $1
      expect((await poolPerformance.tokenPrice(poolLogicProxy.address)).toString()).to.equal(oneDollar.toString());
      expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );

      const ILendingPool = await hre.artifacts.readArtifact("ILendingPool");
      const iLendingPool = new ethers.utils.Interface(ILendingPool.abi);

      // approve usdc
      let approveABI = iERC20.encodeFunctionData("approve", [aave.lendingPool, halfBalanceOfWeth]);
      await poolLogicProxy.connect(manager).execTransaction(assets.weth, approveABI);

      const wethBalanceBefore = await WETH.balanceOf(poolLogicProxy.address);
      const amWethBalanceBefore = await AMWETH.balanceOf(poolLogicProxy.address);

      expect(wethBalanceBefore).to.be.equal(halfBalanceOfWeth);
      expect(amWethBalanceBefore).to.be.equal(0);

      expect((await poolPerformance.tokenPrice(poolLogicProxy.address)).toString()).to.equal(oneDollar.toString());

      // deposit
      let depositABI = iLendingPool.encodeFunctionData("deposit", [
        assets.weth,
        halfBalanceOfWeth,
        poolLogicProxy.address,
        0,
      ]);
      await poolLogicProxy.connect(manager).execTransaction(aave.lendingPool, depositABI);

      const wethBalanceAfter = await WETH.balanceOf(poolLogicProxy.address);
      const amWethBalanceAfter = await AMWETH.balanceOf(poolLogicProxy.address);

      expect(wethBalanceAfter).to.be.equal(0);
      checkAlmostSame(amWethBalanceAfter, halfBalanceOfWeth);

      // Here we are taking some of the logicOwners weth and depositing it directly into the aave Pool as amWETH
      await WETH.approve(aave.lendingPool, halfBalanceOfWeth);
      const AaveLendingPool = await ethers.getContractAt(ILendingPool.abi, aave.lendingPool);
      await AaveLendingPool.deposit(assets.weth, halfBalanceOfWeth, poolLogicProxy.address, 0);

      // All the logicOwners weth is now aWETH half deposited normally, half direct deposited
      checkAlmostSame(await AMWETH.balanceOf(poolLogicProxy.address), balanceOfWeth);

      // We check that the directDeposit of amWeth is accounted for by PoolPerformance
      // We've double the amount of underlying assets so the price should be nearly double
      // We use closeTo here because every block we are getting crumbs as interest on our aAsset which
      // increases the price slightly
      expect(await poolPerformance.tokenPrice(poolLogicProxy.address)).to.be.closeTo(
        ethers.BigNumber.from(BigInt(twoDollar)),
        1e9,
      );

      expect(await poolPerformance.tokenPriceAdjustedForManagerFee(poolLogicProxy.address)).to.be.closeTo(
        ethers.BigNumber.from(BigInt(twoDollar)),
        1e9,
      );

      expect(await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).to.be.closeTo(
        ethers.BigNumber.from(BigInt(twoDollar / 2)),
        1e9,
      );

      expect(await poolPerformance.tokenPriceAdjustedForPerformanceAndManagerFee(poolLogicProxy.address)).to.be.closeTo(
        ethers.BigNumber.from(BigInt(twoDollar / 2)),
        1e9,
      );
    });
  });
});
