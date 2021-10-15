const { ethers, upgrades } = require("hardhat");
const { BigNumber } = ethers;
const { expect, use } = require("chai");
const { solidity } = require("ethereum-waffle");
const { checkAlmostSame, toBytes32, units } = require("../../TestHelpers");
const { sushi, aave, assets, price_feeds } = require("../polygon-data");

use(solidity);

const oneDollar = units(1);
const twoDollar = units(2);
const threeDollar = units(3);

// https://kndrck.co/posts/local_erc20_bal_mani_w_hh/
const setStorageAt = async (address, index, value) => {
  await ethers.provider.send("hardhat_setStorageAt", [address, index, value]);
  await ethers.provider.send("evm_mine", []); // Just mines to the next block
};

describe("PoolPerformance", function () {
  let USDC, WETH, WMatic;
  let logicOwner, manager, dao;
  let PoolLogic;
  let assetHandler, governance, poolFactory, poolLogicProxy, poolPerformance, sushiswapRouter;

  beforeEach(async function () {
    [logicOwner, manager, dao] = await ethers.getSigners();

    const AssetHandlerLogic = await ethers.getContractFactory("AssetHandler");

    const Governance = await ethers.getContractFactory("Governance");
    governance = await Governance.deploy();

    const PoolPerformance = await ethers.getContractFactory("PoolPerformance");
    poolPerformance = await upgrades.deployProxy(PoolPerformance);
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
    WMatic = await ethers.getContractAt(IWETH.abi, assets.wmatic);
    const IERC20 = await hre.artifacts.readArtifact("IERC20");
    USDC = await ethers.getContractAt(IERC20.abi, assets.usdc);
    WETH = await ethers.getContractAt(IERC20.abi, assets.weth);

    const IUniswapV2Router = await hre.artifacts.readArtifact("IUniswapV2Router");
    sushiswapRouter = await ethers.getContractAt(IUniswapV2Router.abi, sushi.router);
    await WMatic.deposit({ value: units(500) });

    // Get USDC
    await WMatic.approve(sushi.router, units(1000));
    await sushiswapRouter.swapExactTokensForTokens(
      units(500),
      0,
      [assets.wmatic, assets.usdc],
      logicOwner.address,
      Math.floor(Date.now() / 1000 + 100000000),
    );
  });

  describe("Existing pools before PoolPerformance deployed", () => {
    // This tests checks that pools that existed but with not funds before PoolPerformance is deployed
    // That they are not penalized
    it("existing pool unitialized without deposit + tokenPriceAdjustedForPerformance", async () => {
      const managerFee = BigNumber.from("0"); // 0%;
      // Create the fund we're going to use for testing
      await poolFactory.createFund(false, manager.address, "Barren Wuffet", "Test Fund", "DHTF", managerFee, [
        [assets.usdc, true],
      ]);
      const funds = await poolFactory.getDeployedFunds();
      poolLogicProxy = await PoolLogic.attach(funds[0]);

      // When pools are created they are set to initialized in PoolPerformance
      // But in this integration test we want to test as though this pool existed
      // Before PoolPerformance was deployed.
      // So we hack the storage of PoolPerformance to mark the Pool as not initialised
      expect(await poolPerformance.poolInitialized(poolLogicProxy.address)).to.equal(true);
      const poolIndex = ethers.utils.solidityKeccak256(
        ["uint256", "uint256"],
        // mapping(address => bool) public poolInitialized; in PoolPerformance.sol
        // is storage slot 101 because of extending contracts with gaps[50]
        // I found this storage slot by looping through every index between 0 and 300 looking for true value
        [poolLogicProxy.address, 101], // key, slot
      );

      expect(
        await ethers.provider.getStorageAt(poolPerformance.address, poolIndex),
        //true
      ).to.equal("0x0000000000000000000000000000000000000000000000000000000000000001");

      await setStorageAt(
        poolPerformance.address,
        poolIndex,
        "0x0000000000000000000000000000000000000000000000000000000000000000",
      );

      expect(
        await ethers.provider.getStorageAt(poolPerformance.address, poolIndex),
        //false
      ).to.equal("0x0000000000000000000000000000000000000000000000000000000000000000");
      expect(await poolPerformance.poolInitialized(poolLogicProxy.address)).to.equal(false);

      // Add some value into the pool directly
      await USDC.transfer(poolLogicProxy.address, (100e6).toString());

      // Deposit $1 conventional way
      await USDC.approve(poolLogicProxy.address, (100e6).toString());
      await poolLogicProxy.deposit(assets.usdc, (100e6).toString());
      // Check tokenPriceAdjustForPerformance() should be $1
      expect((await poolPerformance.tokenPrice(poolLogicProxy.address)).toString()).to.equal(twoDollar.toString());
      expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        twoDollar.toString(),
      );

      // Check hasExternalBalances() == FALSE
      expect(await poolPerformance.hasExternalBalances(poolLogicProxy.address)).to.equal(false);
      // Deposit $1 directly
      await USDC.transfer(poolLogicProxy.address, (100e6).toString());
      // Check TokenPrice() should be $3
      expect((await poolPerformance.tokenPrice(poolLogicProxy.address)).toString()).to.equal(threeDollar.toString());
      // Check tokenPriceAdjustForPerformance == $2; (i.e directDepositFactor $1)
      expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.be.closeTo(
        twoDollar,
        2,
      );
    });

    // This tests checks that pools that existed with funds before PoolPerformance is deployed
    // That they are not penalized
    it("existing pool unintitialized with deposit + tokenPriceAdjustedForPerformance", async () => {
      const managerFee = BigNumber.from("0"); // 0%;
      // Create the fund we're going to use for testing
      await poolFactory.createFund(false, manager.address, "Barren Wuffet", "Test Fund", "DHTF", managerFee, [
        [assets.usdc, true],
      ]);
      const funds = await poolFactory.getDeployedFunds();
      poolLogicProxy = await PoolLogic.attach(funds[0]);

      // Deposit $1 conventional way
      await USDC.approve(poolLogicProxy.address, (100e6).toString());
      await poolLogicProxy.deposit(assets.usdc, (100e6).toString());

      // When pools are created they are set to initialized in PoolPerformance
      // But in this integration test we want to test as though this pool existed
      // Before PoolPerformance was deployed.
      // So we hack the storage of PoolPerformance to mark the Pool as not initialised
      expect(await poolPerformance.poolInitialized(poolLogicProxy.address)).to.equal(true);
      const poolIndex = ethers.utils.solidityKeccak256(
        ["uint256", "uint256"],
        // mapping(address => bool) public poolInitialized; in PoolPerformance.sol
        // is storage slot 101 because of extending contracts with gaps[50]
        // I found this storage slot by looping through every index between 0 and 300 looking for true value
        [poolLogicProxy.address, 101], // key, slot
      );

      expect(
        await ethers.provider.getStorageAt(poolPerformance.address, poolIndex),
        //true
      ).to.equal("0x0000000000000000000000000000000000000000000000000000000000000001");

      await setStorageAt(
        poolPerformance.address,
        poolIndex,
        "0x0000000000000000000000000000000000000000000000000000000000000000",
      );

      expect(
        await ethers.provider.getStorageAt(poolPerformance.address, poolIndex),
        //false
      ).to.equal("0x0000000000000000000000000000000000000000000000000000000000000000");
      expect(await poolPerformance.poolInitialized(poolLogicProxy.address)).to.equal(false);

      // Check tokenPriceAdjustForPerformance() should be $1
      expect((await poolPerformance.tokenPrice(poolLogicProxy.address)).toString()).to.equal(oneDollar.toString());
      expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );

      // Add some value into the pool directly
      await USDC.transfer(poolLogicProxy.address, (100e6).toString());

      // Check tokenPriceAdjustForPerformance() should be $2
      // Because this pool is not initialised in PoolPerformance we ignore direct deposits
      expect((await poolPerformance.tokenPrice(poolLogicProxy.address)).toString()).to.equal(twoDollar.toString());
      expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        twoDollar.toString(),
      );

      // Deposit $1 conventional way
      // This will initialize the pool in PoolPerformance and record it's balances
      await USDC.approve(poolLogicProxy.address, (100e6).toString());
      await poolLogicProxy.deposit(assets.usdc, (100e6).toString());

      // Check tokenPriceAdjustForPerformance() should be $2 still
      expect((await poolPerformance.tokenPrice(poolLogicProxy.address)).toString()).to.equal(twoDollar.toString());
      expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        twoDollar.toString(),
      );

      // Add some value into the pool directly, this should be detected now the pool is initialized in PoolPerformance
      await USDC.transfer(poolLogicProxy.address, (100e6).toString());

      // Check the $1 direct transferered is allocated to token holders
      // TokenPrice should now be more than $2
      expect((await poolPerformance.tokenPrice(poolLogicProxy.address)).toString()).to.equal("2666666666666666666");
      // Check tokenPriceAdjustForPerformance should still be $2; (i.e directDepositFactor $1)
      expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.be.closeTo(
        twoDollar,
        2,
      );
    });
  });
});
