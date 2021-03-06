import { ethers, upgrades } from "hardhat";
import { expect, use } from "chai";
import chaiAlmost from "chai-almost";
import { checkAlmostSame, getAmountOut, units } from "../../TestHelpers";
import { sushi, assets, price_feeds, ZERO_ADDRESS } from "./arbitrum-data";

use(chaiAlmost());

describe("Sushiswap V2 Test", function () {
  let WETH, USDC, SushiLPUSDCWETH, SUSHI;
  let sushiLPAggregator, sushiMiniChefV2Guard;
  let logicOwner, manager, dao, user;
  let PoolFactory, PoolLogic, PoolManagerLogic;
  let poolFactory, poolLogic, poolManagerLogic, poolLogicProxy, poolManagerLogicProxy, fundAddress;

  before(async function () {
    [logicOwner, manager, dao, user] = await ethers.getSigners();

    const AssetHandlerLogic = await ethers.getContractFactory("AssetHandler");

    const Governance = await ethers.getContractFactory("Governance");
    const governance = await Governance.deploy();
    console.log("governance deployed to:", governance.address);

    const PoolPerformance = await ethers.getContractFactory("PoolPerformance");
    const poolPerformance = await upgrades.deployProxy(PoolPerformance, [ZERO_ADDRESS /*aave.protocolDataProvider*/]);
    await poolPerformance.deployed();

    PoolLogic = await ethers.getContractFactory("PoolLogic");
    poolLogic = await PoolLogic.deploy();

    PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
    poolManagerLogic = await PoolManagerLogic.deploy();

    // Initialize Asset Price Consumer
    const assetWeth = { asset: assets.weth, assetType: 0, aggregator: price_feeds.eth };
    const assetUsdt = { asset: assets.usdt, assetType: 0, aggregator: price_feeds.usdt };
    const assetUsdc = { asset: assets.usdc, assetType: 0, aggregator: price_feeds.usdc };
    const assetSushi = { asset: assets.sushi, assetType: 0, aggregator: price_feeds.sushi };
    const assetHandlerInitAssets = [assetWeth, assetUsdt, assetUsdc, assetSushi];

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
    await poolFactory.setExitFee(5, 1000); // 0.5%
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
    await erc20Guard.deployed();

    const UniswapV2RouterGuard = await ethers.getContractFactory("UniswapV2RouterGuard");
    uniswapV2RouterGuard = await UniswapV2RouterGuard.deploy(2, 100); // set slippage 2% for testing
    uniswapV2RouterGuard.deployed();

    const SushiMiniChefV2Guard = await ethers.getContractFactory("SushiMiniChefV2Guard");
    // WARNING WARNING SushiMiniChefV2Guard TAKES TWO ASSETS FOR REWARDS NOT SURE WHAT THEY ARE ON ARB
    sushiMiniChefV2Guard = await SushiMiniChefV2Guard.deploy(assets.sushi, assets.usdt);
    sushiMiniChefV2Guard.deployed();

    const SushiLPAssetGuard = await ethers.getContractFactory("SushiLPAssetGuard");
    sushiLPAssetGuard = await SushiLPAssetGuard.deploy(sushi.minichef); // initialise with Sushi staking pool Id
    sushiLPAssetGuard.deployed();

    await governance.setAssetGuard(0, erc20Guard.address);
    await governance.setAssetGuard(2, sushiLPAssetGuard.address);
    await governance.setContractGuard(sushi.router, uniswapV2RouterGuard.address);
    await governance.setContractGuard(sushi.minichef, sushiMiniChefV2Guard.address);
  });

  it("Should be able to get USDC", async function () {
    const IWETH = await hre.artifacts.readArtifact("IWETH");
    Weth = await ethers.getContractAt(IWETH.abi, assets.weth);
    const IERC20 = await hre.artifacts.readArtifact("IERC20");
    USDT = await ethers.getContractAt(IERC20.abi, assets.usdt);
    USDC = await ethers.getContractAt(IERC20.abi, assets.usdc);
    WETH = await ethers.getContractAt(IERC20.abi, assets.weth);
    SUSHI = await ethers.getContractAt(IERC20.abi, assets.sushi);
    SushiLPUSDCWETH = await ethers.getContractAt(IERC20.abi, sushi.pools.usdc_weth.address);
    let balance = await ethers.provider.getBalance(logicOwner.address);
    console.log("Eth balance: ", balance.toString());
    balance = await Weth.balanceOf(logicOwner.address);
    console.log("Weth balance: ", balance.toString());
    const IUniswapV2Router = await hre.artifacts.readArtifact("IUniswapV2Router");
    const sushiswapRouter = await ethers.getContractAt(IUniswapV2Router.abi, sushi.router);
    // deposit Eth -> WETH
    await Weth.deposit({ value: units(1) });
    balance = await Weth.balanceOf(logicOwner.address);
    console.log("Weth balance: ", balance.toString());
    // Weth -> USDC
    console.log("USDC balance: ", balance.toString());
    await Weth.approve(sushi.router, units(1));

    await sushiswapRouter.swapExactTokensForTokens(
      units(1),
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
      "200",
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
          performanceFeeNumerator,
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
            performanceFeeNumerator: performanceFeeNumerator,
            managerFeeNumerator,
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
        new ethers.BigNumber.from("0"), // 0% streaming fee
        [
          [assets.usdc, true],
          [assets.weth, true],
        ],
        14250,
      ),
    ).to.be.revertedWith("invalid manager fee");

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

    const event = await fundCreatedEvent;

    fundAddress = event.fundAddress;
    expect(event.isPoolPrivate).to.be.false;
    expect(event.fundName).to.equal("Test Fund");
    // expect(event.fundSymbol).to.equal("DHTF");
    expect(event.managerName).to.equal("Barren Wuffet");
    expect(event.manager).to.equal(manager.address);
    expect(event.performanceFeeNumerator.toString()).to.equal("5000");
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
    expect(await poolManagerLogicProxy.isSupportedAsset(assets.weth)).to.be.true;

    //Other assets are not supported
    expect(await poolManagerLogicProxy.isSupportedAsset(assets.usdt)).to.be.false;
  });

  it("should be able to deposit", async function () {
    const depositEvent = new Promise((resolve, reject) => {
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

    await expect(poolLogicProxy.deposit(assets.usdt, (200e6).toString())).to.be.revertedWith("invalid deposit asset");

    await USDC.approve(poolLogicProxy.address, (200e6).toString());
    await poolLogicProxy.deposit(assets.usdc, (200e6).toString());
    const event = await depositEvent;

    expect(event.fundAddress).to.equal(poolLogicProxy.address);
    expect(event.investor).to.equal(logicOwner.address);
    checkAlmostSame(event.valueDeposited, units(200));
    checkAlmostSame(event.fundTokensReceived, units(200));
    checkAlmostSame(event.totalInvestorFundTokens, units(200));
    checkAlmostSame(event.fundValue, units(200));
    checkAlmostSame(event.totalSupply, units(200));
  });

  it("Should be able to approve", async () => {
    const IERC20 = await hre.artifacts.readArtifact("IERC20");
    const iERC20 = new ethers.utils.Interface(IERC20.abi);
    let approveABI = iERC20.encodeFunctionData("approve", [assets.usdc, (200e6).toString()]);
    await expect(poolLogicProxy.connect(manager).execTransaction(assets.usdt, approveABI)).to.be.revertedWith(
      "asset not enabled in pool",
    );

    await expect(poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI)).to.be.revertedWith(
      "unsupported spender approval",
    );

    approveABI = iERC20.encodeFunctionData("approve", [sushi.router, (200e6).toString()]);
    await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);
  });

  it("should be able to swap tokens on sushiswap.", async () => {
    const exchangeEvent = new Promise((resolve, reject) => {
      uniswapV2RouterGuard.on(
        "ExchangeFrom",
        (managerLogicAddress, sourceAsset, sourceAmount, destinationAsset, time, event) => {
          event.removeListener();

          resolve({
            managerLogicAddress: managerLogicAddress,
            sourceAsset: sourceAsset,
            sourceAmount: sourceAmount,
            destinationAsset: destinationAsset,
            time: time,
          });
        },
      );

      setTimeout(() => {
        reject(new Error("timeout"));
      }, 60000);
    });

    const sourceAmount = (100e6).toString();
    const IUniswapV2Router = await hre.artifacts.readArtifact("IUniswapV2Router");
    const iSushiswapV2Router = new ethers.utils.Interface(IUniswapV2Router.abi);
    let swapABI = iSushiswapV2Router.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      0,
      [assets.usdc, assets.weth],
      poolManagerLogicProxy.address,
      0,
    ]);

    await expect(
      poolLogicProxy.connect(manager).execTransaction("0x0000000000000000000000000000000000000000", swapABI),
    ).to.be.revertedWith("non-zero address is required");

    swapABI = iSushiswapV2Router.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      0,
      [assets.usdt, assets.weth],
      poolLogicProxy.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(assets.usdc, swapABI)).to.be.revertedWith(
      "invalid transaction",
    );

    swapABI = iSushiswapV2Router.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      0,
      [assets.usdc, assets.weth, assets.usdt],
      poolLogicProxy.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(sushi.router, swapABI)).to.be.revertedWith(
      "unsupported destination asset",
    );

    swapABI = iSushiswapV2Router.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      0,
      [assets.usdc, assets.weth],
      user.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(sushi.router, swapABI)).to.be.revertedWith(
      "recipient is not pool",
    );

    swapABI = iSushiswapV2Router.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      await getAmountOut(sushi.router, sourceAmount, [assets.usdc, assets.weth]),
      [assets.usdc, assets.weth],
      poolLogicProxy.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(sushi.router, swapABI)).to.be.revertedWith(
      "UniswapV2Router: EXPIRED",
    );

    swapABI = iSushiswapV2Router.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      await getAmountOut(sushi.router, sourceAmount, [assets.usdc, assets.weth]),
      [assets.usdc, assets.weth],
      poolLogicProxy.address,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);
    await poolLogicProxy.connect(manager).execTransaction(sushi.router, swapABI);

    expect(await USDC.balanceOf(poolLogicProxy.address)).to.be.equal(100e6);
    const event = await exchangeEvent;
    expect(event.sourceAsset).to.equal(assets.usdc);
    expect(event.sourceAmount).to.equal((100e6).toString());
    expect(event.destinationAsset.toLowerCase()).to.equal(assets.weth.toLowerCase());
  });

  it("should be able to withdraw", async function () {
    const withdrawalEvent = new Promise((resolve, reject) => {
      poolLogicProxy.on(
        "Withdrawal",
        (
          fundAddress,
          investor,
          valueWithdrawn,
          fundTokensWithdrawn,
          totalInvestorFundTokens,
          fundValue,
          totalSupply,
          withdrawnAssets,
          time,
          event,
        ) => {
          event.removeListener();

          resolve({
            fundAddress: fundAddress,
            investor: investor,
            valueWithdrawn: valueWithdrawn,
            fundTokensWithdrawn: fundTokensWithdrawn,
            totalInvestorFundTokens: totalInvestorFundTokens,
            fundValue: fundValue,
            totalSupply: totalSupply,
            withdrawnAssets: withdrawnAssets,
            time: time,
          });
        },
      );

      setTimeout(() => {
        reject(new Error("timeout"));
      }, 60000);
    });

    // Withdraw 50%
    const withdrawAmount = units(100);

    await poolFactory.setExitCooldown(0);

    await poolLogicProxy.withdraw(withdrawAmount);

    const event = await withdrawalEvent;
    expect(event.fundAddress).to.equal(poolLogicProxy.address);
    expect(event.investor).to.equal(logicOwner.address);
    checkAlmostSame(event.valueWithdrawn, units(100));
    checkAlmostSame(event.fundTokensWithdrawn, units(100));
    checkAlmostSame(event.totalInvestorFundTokens, units(100));
    checkAlmostSame(event.fundValue, units(100));
    checkAlmostSame(event.totalSupply, units(100));
  });

  describe("Staking", () => {
    let availableLpToken, iMiniChefV2;

    const stakeAvailableLpTokens = async () => {
      availableLpToken = await SushiLPUSDCWETH.balanceOf(poolLogicProxy.address);

      const IMiniChefV2 = await hre.artifacts.readArtifact("IMiniChefV2");
      iMiniChefV2 = new ethers.utils.Interface(IMiniChefV2.abi);
      const depositAbi = iMiniChefV2.encodeFunctionData("deposit", [
        sushi.pools.usdc_weth.poolId,
        availableLpToken,
        poolLogicProxy.address,
      ]);

      const IERC20 = await hre.artifacts.readArtifact("IERC20");
      const iERC20 = new ethers.utils.Interface(IERC20.abi);
      const approveABI = iERC20.encodeFunctionData("approve", [sushi.minichef, availableLpToken]);
      await poolLogicProxy.connect(manager).execTransaction(sushi.pools.usdc_weth.address, approveABI);
      await poolLogicProxy.connect(manager).execTransaction(sushi.minichef, depositAbi);
    };

    it("manager can add liquidity", async () => {
      await poolManagerLogicProxy.connect(manager).changeAssets([[sushi.pools.usdc_weth.address, false]], []);

      const tokenA = assets.usdc;
      const tokenB = assets.weth;
      const amountADesired = await USDC.balanceOf(poolLogicProxy.address);
      const amountBDesired = await WETH.balanceOf(poolLogicProxy.address);
      const IUniswapV2Router = await hre.artifacts.readArtifact("IUniswapV2Router");
      const iUniswapV2Router = new ethers.utils.Interface(IUniswapV2Router.abi);
      const addLiquidityAbi = iUniswapV2Router.encodeFunctionData("addLiquidity", [
        tokenA,
        tokenB,
        amountADesired,
        amountBDesired,
        0,
        0,
        poolLogicProxy.address,
        Math.floor(Date.now() / 1000 + 100000000),
      ]);

      const IERC20 = await hre.artifacts.readArtifact("IERC20");
      const iERC20 = new ethers.utils.Interface(IERC20.abi);
      let approveABI = iERC20.encodeFunctionData("approve", [sushi.router, amountADesired]);
      await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);
      approveABI = iERC20.encodeFunctionData("approve", [sushi.router, amountBDesired]);
      await poolLogicProxy.connect(manager).execTransaction(assets.weth, approveABI);

      const lpBalanceBefore = await SushiLPUSDCWETH.balanceOf(poolLogicProxy.address);
      const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
      const wethBalanceBefore = await WETH.balanceOf(poolLogicProxy.address);
      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      expect(lpBalanceBefore).to.be.equal(0);

      await poolLogicProxy.connect(manager).execTransaction(sushi.router, addLiquidityAbi);

      expect(await SushiLPUSDCWETH.balanceOf(poolLogicProxy.address)).to.be.gt(lpBalanceBefore);
      expect(await USDC.balanceOf(poolLogicProxy.address)).to.be.lt(usdcBalanceBefore);
      expect(await WETH.balanceOf(poolLogicProxy.address)).to.be.lt(wethBalanceBefore);
      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
    });

    it("manager can Stake Sushi LP token", async () => {
      const stakeEvent = new Promise((resolve, reject) => {
        sushiMiniChefV2Guard.on("Stake", (fundAddress, asset, stakingContract, amount, time, event) => {
          event.removeListener();

          resolve({
            fundAddress,
            asset,
            stakingContract,
            amount,
            time,
          });
        });

        setTimeout(() => {
          reject(new Error("timeout"));
        }, 60000);
      });

      availableLpToken = await SushiLPUSDCWETH.balanceOf(poolLogicProxy.address);

      const IMiniChefV2 = await hre.artifacts.readArtifact("IMiniChefV2");
      iMiniChefV2 = new ethers.utils.Interface(IMiniChefV2.abi);
      const depositAbi = iMiniChefV2.encodeFunctionData("deposit", [
        sushi.pools.usdc_weth.poolId,
        availableLpToken,
        poolLogicProxy.address,
      ]);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      const sushiLPPrice = await assetHandler.getUSDPrice(sushi.pools.usdc_weth.address);
      expect(totalFundValueBefore).to.gte(
        sushiLPPrice.mul(availableLpToken).div(ethers.BigNumber.from((1e18).toString())),
      ); // should at least account for the staked tokens

      // attempt to deposit with manager as recipient
      const badDepositAbi = iMiniChefV2.encodeFunctionData("deposit", [
        sushi.pools.usdc_weth.poolId,
        availableLpToken,
        manager.address,
      ]);

      await expect(poolLogicProxy.connect(manager).execTransaction(sushi.minichef, badDepositAbi)).to.be.revertedWith(
        "recipient is not pool",
      );

      await expect(poolLogicProxy.connect(manager).execTransaction(sushi.minichef, depositAbi)).to.be.revertedWith(
        "enable rewardA token",
      );

      // enable SUSHI token in pool
      await poolManagerLogicProxy.connect(manager).changeAssets([[assets.sushi, false]], []);

      await expect(poolLogicProxy.connect(manager).execTransaction(sushi.minichef, depositAbi)).to.be.revertedWith(
        "enable rewardB token",
      );

      // enable usdt token in pool it is the other reward token
      await poolManagerLogicProxy.connect(manager).changeAssets([[assets.usdt, false]], []);

      const IERC20 = await hre.artifacts.readArtifact("IERC20");
      const iERC20 = new ethers.utils.Interface(IERC20.abi);
      const approveABI = iERC20.encodeFunctionData("approve", [sushi.minichef, availableLpToken]);
      await poolLogicProxy.connect(manager).execTransaction(sushi.pools.usdc_weth.address, approveABI);

      await poolLogicProxy.connect(manager).execTransaction(sushi.minichef, depositAbi);

      expect(await poolManagerLogicProxy.assetBalance(sushi.pools.usdc_weth.address)).to.be.equal(availableLpToken);
      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);

      const event = await stakeEvent;
      expect(event.fundAddress).to.equal(poolLogicProxy.address);
      expect(event.asset.toLowerCase()).to.equal(sushi.pools.usdc_weth.address.toLowerCase());
      expect(event.stakingContract).to.equal(sushi.minichef);
      expect(event.amount).to.equal(availableLpToken);
    });

    it("manager can Unstake Sushi LP token", async function () {
      const unstakeEvent = new Promise((resolve, reject) => {
        sushiMiniChefV2Guard.on("Unstake", (fundAddress, asset, stakingContract, amount, time, event) => {
          event.removeListener();

          resolve({
            fundAddress,
            asset,
            stakingContract,
            amount,
            time,
          });
        });

        setTimeout(() => {
          reject(new Error("timeout"));
        }, 60000);
      });

      // attempt to withdraw with manager as recipient
      const badWithdrawAbi = iMiniChefV2.encodeFunctionData("withdraw", [
        sushi.pools.usdc_weth.poolId,
        availableLpToken,
        manager.address,
      ]);

      await expect(poolLogicProxy.connect(manager).execTransaction(sushi.minichef, badWithdrawAbi)).to.be.revertedWith(
        "recipient is not pool",
      );

      const withdrawAbi = iMiniChefV2.encodeFunctionData("withdraw", [
        sushi.pools.usdc_weth.poolId,
        availableLpToken,
        poolLogicProxy.address,
      ]);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      await poolLogicProxy.connect(manager).execTransaction(sushi.minichef, withdrawAbi);

      expect(await poolManagerLogicProxy.assetBalance(sushi.pools.usdc_weth.address)).to.be.equal(availableLpToken);
      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);

      const event = await unstakeEvent;
      expect(event.fundAddress).to.equal(poolLogicProxy.address);
      expect(event.asset).to.equal(sushi.pools.usdc_weth.address);
      expect(event.stakingContract).to.equal(sushi.minichef);
      expect(event.amount).to.equal(availableLpToken);
    });

    it("manager can Harvest staked Sushi LP token", async function () {
      const claimEvent = new Promise((resolve, reject) => {
        sushiMiniChefV2Guard.on("Claim", (fundAddress, stakingContract, time, event) => {
          event.removeListener();

          resolve({
            fundAddress,
            stakingContract,
            time,
          });
        });

        setTimeout(() => {
          reject(new Error("timeout"));
        }, 60000);
      });

      const harvestAbi = iMiniChefV2.encodeFunctionData("harvest", [
        sushi.pools.usdc_weth.poolId,
        poolLogicProxy.address,
      ]);

      // attempt to harvest with manager as recipient
      const badHarvestAbi = iMiniChefV2.encodeFunctionData("withdraw", [
        sushi.pools.usdc_weth.poolId,
        availableLpToken,
        manager.address,
      ]);

      await expect(poolLogicProxy.connect(manager).execTransaction(sushi.minichef, badHarvestAbi)).to.be.revertedWith(
        "recipient is not pool",
      );

      expect(await SUSHI.balanceOf(poolLogicProxy.address)).to.be.equal(0);

      await poolLogicProxy.connect(manager).execTransaction(sushi.minichef, harvestAbi);

      const event = await claimEvent;
      expect(event.fundAddress).to.equal(poolLogicProxy.address);
      expect(event.stakingContract).to.equal(sushi.minichef);

      expect(await SUSHI.balanceOf(poolLogicProxy.address)).to.be.gt(0);
    });

    it("manager can Withdraw And Harvest staked Sushi LP token", async function () {
      await stakeAvailableLpTokens();

      const unstakeEvent = new Promise((resolve, reject) => {
        sushiMiniChefV2Guard.on("Unstake", (fundAddress, asset, stakingContract, amount, time, event) => {
          event.removeListener();

          resolve({
            fundAddress,
            asset,
            stakingContract,
            amount,
            time,
          });
        });

        setTimeout(() => {
          reject(new Error("timeout"));
        }, 60000);
      });

      const claimEvent = new Promise((resolve, reject) => {
        sushiMiniChefV2Guard.on("Claim", (fundAddress, stakingContract, time, event) => {
          event.removeListener();

          resolve({
            fundAddress,
            stakingContract,
            time,
          });
        });

        setTimeout(() => {
          reject(new Error("timeout"));
        }, 60000);
      });

      // manager attempts to withdraw to themselves
      let badWithdrawAndHarvestAbi = iMiniChefV2.encodeFunctionData("withdrawAndHarvest", [
        sushi.pools.usdc_weth.poolId,
        availableLpToken,
        manager.address,
      ]);

      await expect(
        poolLogicProxy.connect(manager).execTransaction(sushi.minichef, badWithdrawAndHarvestAbi),
      ).to.be.revertedWith("recipient is not pool");

      // manager attempts to withdraw unknown LP token
      badWithdrawAndHarvestAbi = iMiniChefV2.encodeFunctionData("withdrawAndHarvest", [
        sushi.pools.usdc_weth.poolId + 1,
        availableLpToken,
        poolLogicProxy.address,
      ]);

      await expect(
        poolLogicProxy.connect(manager).execTransaction(sushi.minichef, badWithdrawAndHarvestAbi),
      ).to.be.revertedWith("unsupported lp asset");

      const withdrawAndHarvestAbi = iMiniChefV2.encodeFunctionData("withdrawAndHarvest", [
        sushi.pools.usdc_weth.poolId,
        availableLpToken,
        poolLogicProxy.address,
      ]);

      const sushiBalanceBefore = await SUSHI.balanceOf(poolLogicProxy.address);
      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      await ethers.provider.send("evm_increaseTime", [3600 * 24]);
      await poolLogicProxy.connect(manager).execTransaction(sushi.minichef, withdrawAndHarvestAbi);

      expect(await SUSHI.balanceOf(poolLogicProxy.address)).to.be.gt(sushiBalanceBefore);
      expect(await poolManagerLogicProxy.totalFundValue()).to.be.gt(totalFundValueBefore);

      const eventUnstake = await unstakeEvent;
      expect(eventUnstake.fundAddress).to.equal(poolLogicProxy.address);
      expect(eventUnstake.asset).to.equal(sushi.pools.usdc_weth.address);
      expect(eventUnstake.stakingContract).to.equal(sushi.minichef);
      expect(eventUnstake.amount).to.equal(availableLpToken);

      const eventClaim = await claimEvent;
      expect(eventClaim.fundAddress).to.equal(poolLogicProxy.address);
      expect(eventClaim.stakingContract).to.equal(sushi.minichef);
    });

    it("investor can Withdraw staked Sushi LP token", async function () {
      await stakeAvailableLpTokens();

      const withdrawalEvent = new Promise((resolve, reject) => {
        poolLogicProxy.on(
          "Withdrawal",
          (
            fundAddress,
            investor,
            valueWithdrawn,
            fundTokensWithdrawn,
            totalInvestorFundTokens,
            fundValue,
            totalSupply,
            withdrawnAssets,
            time,
            event,
          ) => {
            event.removeListener();

            resolve({
              fundAddress: fundAddress,
              investor: investor,
              valueWithdrawn: valueWithdrawn,
              fundTokensWithdrawn: fundTokensWithdrawn,
              totalInvestorFundTokens: totalInvestorFundTokens,
              fundValue: fundValue,
              totalSupply: totalSupply,
              withdrawnAssets: withdrawnAssets,
              time: time,
            });
          },
        );

        setTimeout(() => {
          reject(new Error("timeout"));
        }, 60000);
      });

      // remove manager fee so that performance fee minting doesn't get in the way
      await poolManagerLogicProxy.connect(manager).setFeeNumerator("0");

      const totalSupply = await poolLogicProxy.totalSupply();

      const totalFundValue = await poolManagerLogicProxy.totalFundValue();
      const usdcBalance = await USDC.balanceOf(poolLogicProxy.address);
      const wethBalance = await WETH.balanceOf(poolLogicProxy.address);
      const usdcPrice = await assetHandler.getUSDPrice(assets.usdc);
      const wethPrice = await assetHandler.getUSDPrice(assets.weth);
      const sushiLPPrice = await assetHandler.getUSDPrice(sushi.pools.usdc_weth.address);
      const expectedFundValue = usdcBalance
        .mul(usdcPrice)
        .div(ethers.BigNumber.from("1000000"))
        .add(wethBalance.mul(wethPrice).div(units(1)))
        .add(availableLpToken.mul(sushiLPPrice).div(units(1)));

      checkAlmostSame(totalFundValue, expectedFundValue.toString());

      // Withdraw all
      const withdrawAmount = units(10);
      const investorFundBalance = await poolLogicProxy.balanceOf(logicOwner.address);

      const sushiBalanceBefore = await SUSHI.balanceOf(logicOwner.address);
      const lpBalanceBefore = await SushiLPUSDCWETH.balanceOf(logicOwner.address);

      ethers.provider.send("evm_increaseTime", [3600 * 24]); // add 1 day to avoid cooldown revert
      await poolLogicProxy.withdraw(withdrawAmount);

      const eventWithdrawal = await withdrawalEvent;

      const valueWithdrawn = withdrawAmount.mul(totalFundValue).div(totalSupply);
      const expectedFundValueAfter = totalFundValue.sub(valueWithdrawn);

      expect(await SUSHI.balanceOf(logicOwner.address)).to.be.gt(sushiBalanceBefore);
      expect(await SushiLPUSDCWETH.balanceOf(logicOwner.address)).to.be.gt(lpBalanceBefore);

      expect(eventWithdrawal.fundAddress).to.equal(poolLogicProxy.address);
      expect(eventWithdrawal.investor).to.equal(logicOwner.address);
      checkAlmostSame(eventWithdrawal.valueWithdrawn, valueWithdrawn.toString());
      expect(eventWithdrawal.fundTokensWithdrawn).to.equal(withdrawAmount.toString());
      checkAlmostSame(eventWithdrawal.totalInvestorFundTokens, (investorFundBalance - withdrawAmount).toString());
      checkAlmostSame(eventWithdrawal.fundValue, expectedFundValueAfter);
      checkAlmostSame(eventWithdrawal.totalSupply, (totalSupply - withdrawAmount).toString());
    });
  });
});
