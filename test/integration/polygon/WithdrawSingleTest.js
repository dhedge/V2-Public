const { ethers, upgrades } = require("hardhat");
const { expect, use } = require("chai");
const chaiAlmost = require("chai-almost");
const { checkAlmostSame, toBytes32, getAmountOut, units } = require("../../TestHelpers");
const { aave, quickswap, assets, price_feeds } = require("../polygon-data");

use(chaiAlmost());

describe("WithdrawSingle Test", function () {
  let WMatic, WETH, USDC, QuickLPUSDCWETH, QUICK;
  let logicOwner, manager, dao, user;
  let PoolLogic, PoolManagerLogic;
  let poolFactory,
    poolLogic,
    poolManagerLogic,
    poolLogicProxy,
    poolManagerLogicProxy,
    fundAddress,
    uniswapV2RouterGuard;

  before(async function () {
    [logicOwner, manager, dao, user] = await ethers.getSigners();

    const AssetHandlerLogic = await ethers.getContractFactory("AssetHandler");

    const Governance = await ethers.getContractFactory("Governance");
    const governance = await Governance.deploy();
    console.log("governance deployed to:", governance.address);

    const PoolPerformance = await ethers.getContractFactory("PoolPerformance");
    const poolPerformance = await upgrades.deployProxy(PoolPerformance, []);
    await poolPerformance.deployed();

    PoolLogic = await ethers.getContractFactory("PoolLogic");
    poolLogic = await PoolLogic.deploy();

    PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
    poolManagerLogic = await PoolManagerLogic.deploy();

    // Initialize Asset Price Consumer
    const assetWeth = { asset: assets.weth, assetType: 0, aggregator: price_feeds.eth };
    const assetUsdt = { asset: assets.usdt, assetType: 0, aggregator: price_feeds.usdt };
    const assetUsdc = { asset: assets.usdc, assetType: 0, aggregator: price_feeds.usdc };
    const assetHandlerInitAssets = [assetWeth, assetUsdt, assetUsdc];

    const assetHandler = await upgrades.deployProxy(AssetHandlerLogic, [assetHandlerInitAssets]);
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

    // Deploy Quick LP Aggregator
    const UniV2LPAggregator = await ethers.getContractFactory("UniV2LPAggregator");
    const quickLPAggregator = await UniV2LPAggregator.deploy(quickswap.pools.usdc_weth.address, poolFactory.address);
    const assetQuickLPWethUsdc = {
      asset: quickswap.pools.usdc_weth.address,
      assetType: 5,
      aggregator: quickLPAggregator.address,
    };
    await assetHandler.addAssets([assetQuickLPWethUsdc]);

    const ERC20Guard = await ethers.getContractFactory("ERC20Guard");
    const erc20Guard = await ERC20Guard.deploy();
    await erc20Guard.deployed();

    const OpenAssetGuard = await ethers.getContractFactory("OpenAssetGuard");
    const openAssetGuard = await OpenAssetGuard.deploy([assets.wmatic, assets.quick]);
    await openAssetGuard.deployed();

    const UniswapV2RouterGuard = await ethers.getContractFactory("UniswapV2RouterGuard");
    uniswapV2RouterGuard = await UniswapV2RouterGuard.deploy(2, 100); // set slippage 2% for testing
    await uniswapV2RouterGuard.deployed();

    await governance.setAssetGuard(0, erc20Guard.address);
    await governance.setContractGuard(quickswap.router, uniswapV2RouterGuard.address);
    await governance.setAddresses([[toBytes32("openAssetGuard"), openAssetGuard.address]]);

    await poolFactory.setExitFee(5, 1000); // 0.5%
  });

  it("Should be able to get USDC", async function () {
    const IWETH = await hre.artifacts.readArtifact("IWETH");
    WMatic = await ethers.getContractAt(IWETH.abi, assets.wmatic);
    const IERC20 = await hre.artifacts.readArtifact("IERC20");
    USDT = await ethers.getContractAt(IERC20.abi, assets.usdt);
    USDC = await ethers.getContractAt(IERC20.abi, assets.usdc);
    WETH = await ethers.getContractAt(IERC20.abi, assets.weth);
    WMATIC = await ethers.getContractAt(IERC20.abi, assets.wmatic);
    QUICK = await ethers.getContractAt(IERC20.abi, assets.quick);
    QuickLPUSDCWETH = await ethers.getContractAt(IERC20.abi, quickswap.pools.usdc_weth.address);
    let balance = await ethers.provider.getBalance(logicOwner.address);
    console.log("Matic balance: ", balance.toString());
    balance = await WMATIC.balanceOf(logicOwner.address);
    console.log("WMatic balance: ", balance.toString());
    const IUniswapV2Router = await hre.artifacts.readArtifact("IUniswapV2Router");
    const QuickSwapRouter = await ethers.getContractAt(IUniswapV2Router.abi, quickswap.router);
    // deposit Matic -> WMatic
    await WMatic.deposit({ value: units(1000) });
    balance = await WMATIC.balanceOf(logicOwner.address);
    console.log("WMatic balance: ", balance.toString());
    // WMatic -> USDC
    await WMatic.approve(quickswap.router, units(1000));
    await QuickSwapRouter.swapExactTokensForTokens(
      units(1000),
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

    const fundCreatedEvent = new Promise((resolve, reject) => {
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
      [
        [assets.usdc, true],
        [assets.usdt, true],
      ],
    );

    const event = await fundCreatedEvent;

    fundAddress = event.fundAddress;
    expect(event.isPoolPrivate).to.be.false;
    expect(event.fundName).to.equal("Test Fund");
    // expect(event.fundSymbol).to.equal("DHTF");
    expect(event.managerName).to.equal("Barren Wuffet");
    expect(event.manager).to.equal(manager.address);
    expect(event.managerFeeNumerator.toString()).to.equal("5000");
    expect(event.managerFeeDenominator.toString()).to.equal("10000");

    const deployedFunds = await poolFactory.getDeployedFunds();
    const deployedFundsLength = deployedFunds.length;
    expect(deployedFundsLength.toString()).to.equal("1");

    const isPool = await poolFactory.isPool(fundAddress);
    expect(isPool).to.be.true;

    const poolManagerLogicAddress = await poolFactory.getLogic(1);
    expect(poolManagerLogicAddress).to.equal(poolManagerLogic.address);

    const poolLogicAddress = await poolFactory.getLogic(2);
    expect(poolLogicAddress).to.equal(poolLogic.address);

    poolLogicProxy = await PoolLogic.attach(fundAddress);
    const poolManagerLogicProxyAddress = await poolLogicProxy.poolManagerLogic();
    poolManagerLogicProxy = await PoolManagerLogic.attach(poolManagerLogicProxyAddress);

    //default assets are supported
    const supportedAssets = await poolManagerLogicProxy.getSupportedAssets();
    const numberOfSupportedAssets = supportedAssets.length;
    expect(numberOfSupportedAssets).to.eq(2);
    expect(await poolManagerLogicProxy.isSupportedAsset(assets.usdc)).to.be.true;
    expect(await poolManagerLogicProxy.isSupportedAsset(assets.usdt)).to.be.true;

    //Other assets are not supported
    expect(await poolManagerLogicProxy.isSupportedAsset(assets.wmatic)).to.be.false;
  });

  it("Deposit 1000 USDC", async function () {
    const supportedAssets = await poolManagerLogicProxy.getSupportedAssets();
    console.log("supportedAsset: ", supportedAssets);

    const chainlinkEth = await ethers.getContractAt("AggregatorV3Interface", price_feeds.eth);
    const ethPrice = await chainlinkEth.latestRoundData();
    console.log("eth price: ", ethPrice[1].toString());
    console.log("updatedAt: ", ethPrice[3].toString());

    const chainlinkUsdc = await ethers.getContractAt("AggregatorV3Interface", price_feeds.usdc);
    const usdcPrice = await chainlinkUsdc.latestRoundData();
    console.log("usdc price: ", usdcPrice[1].toString());
    console.log("updatedAt: ", usdcPrice[3].toString());

    // Revert on second time
    const assetBalance = await poolManagerLogicProxy.assetBalance(assets.usdc);
    console.log("assetBalance: ", assetBalance.toString());

    // Revert on second time
    const assetValue = await poolManagerLogicProxy["assetValue(address)"](assets.usdc);
    console.log("assetValue: ", assetValue.toString());

    // Revert on second time
    totalFundValue = await poolManagerLogicProxy.totalFundValue();
    expect(totalFundValue.toString()).to.equal("0");

    await expect(poolLogicProxy.deposit(assets.wmatic, units(1000, 6).toString())).to.be.revertedWith(
      "invalid deposit asset",
    );

    await USDC.approve(poolLogicProxy.address, units(1000, 6).toString());
    await poolLogicProxy.deposit(assets.usdc, units(1000, 6).toString());
  });

  it("Approve 750 USDC", async () => {
    const IERC20 = await hre.artifacts.readArtifact("IERC20");
    const iERC20 = new ethers.utils.Interface(IERC20.abi);
    const approveABI = iERC20.encodeFunctionData("approve", [quickswap.router, units(750, 6).toString()]);
    await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);
  });

  it("Swap 750 USDC to WETH", async () => {
    await poolManagerLogicProxy.connect(manager).changeAssets([[assets.weth, false]], []);

    const sourceAmount = units(750, 6);
    const IUniswapV2Router = await hre.artifacts.readArtifact("IUniswapV2Router");
    const iQuickswapRouter = new ethers.utils.Interface(IUniswapV2Router.abi);
    const swapABI = iQuickswapRouter.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      await getAmountOut(quickswap.router, sourceAmount, [assets.usdc, assets.weth]),
      [assets.usdc, assets.weth],
      poolLogicProxy.address,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);
    await poolLogicProxy.connect(manager).execTransaction(quickswap.router, swapABI);

    checkAlmostSame(await USDC.balanceOf(poolLogicProxy.address), units(250, 6));
  });

  it("not able to withdrawSingle 300 USDC", async function () {
    ethers.provider.send("evm_increaseTime", [3600 * 24]); // add 1 day to avoid cooldown revert
    await expect(poolLogicProxy.withdrawSingle(units(10000), assets.usdc)).to.be.revertedWith("insufficient balance");

    const withdrawAmount = units(300);
    await expect(poolLogicProxy.withdrawSingle(withdrawAmount, assets.quick)).to.be.revertedWith(
      "invalid deposit asset",
    );
    await expect(poolLogicProxy.withdrawSingle(withdrawAmount, assets.usdc)).to.be.revertedWith(
      "insufficient asset amount",
    );

    const withdrawMaxAmount = await poolLogicProxy.getWithdrawSingleMax(assets.usdc);
    checkAlmostSame(withdrawMaxAmount, units(250).mul(101).div(100));
  });

  // Disabled early withdraw for now
  // it("able to withdrawSingle 200 USDC (early withdraw)", async function () {
  //   const withdrawAmount = units(200);

  //   const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
  //   const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
  //   const withdrawMaxAmountBefore = await poolLogicProxy.getWithdrawSingleMax(assets.usdc);

  //   await poolLogicProxy.withdrawSingle(withdrawAmount, assets.usdc);

  //   const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
  //   const totalFundValueAfter = await poolManagerLogicProxy.totalFundValue();

  //   // check with remove 0.5% exit fee
  //   checkAlmostSame(usdcBalanceBefore, units(199, 6).add(usdcBalanceAfter));
  //   checkAlmostSame(totalFundValueBefore, units(199).add(totalFundValueAfter));

  //   checkAlmostSame(
  //     withdrawMaxAmountBefore,
  //     withdrawAmount.add(await poolLogicProxy.getWithdrawSingleMax(assets.usdc)),
  //   );
  // });

  it("able to withdrawSingle 20 USDC", async function () {
    const withdrawAmount = units(20);

    const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
    const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
    const withdrawMaxAmountBefore = await poolLogicProxy.getWithdrawSingleMax(assets.usdc);

    ethers.provider.send("evm_increaseTime", [3600 * 24]); // add 1 day to avoid cooldown revert
    await poolLogicProxy.withdrawSingle(withdrawAmount, assets.usdc);

    const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
    const totalFundValueAfter = await poolManagerLogicProxy.totalFundValue();

    checkAlmostSame(usdcBalanceBefore, units(20, 6).add(usdcBalanceAfter));
    checkAlmostSame(totalFundValueBefore, units(20).add(totalFundValueAfter));

    checkAlmostSame(
      withdrawMaxAmountBefore,
      withdrawAmount.add(await poolLogicProxy.getWithdrawSingleMax(assets.usdc)),
    );
  });
});
