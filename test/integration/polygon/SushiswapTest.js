const { ethers, upgrades } = require("hardhat");
const { expect, use } = require("chai");
const chaiAlmost = require("chai-almost");

use(chaiAlmost());

const checkAlmostSame = (a, b) => {
  expect(ethers.BigNumber.from(a).gte(ethers.BigNumber.from(b).mul(99).div(100))).to.be.true;
  expect(ethers.BigNumber.from(a).lte(ethers.BigNumber.from(b).mul(101).div(100))).to.be.true;
};

const units = (value) => ethers.utils.parseUnits(value.toString());

const sushiswapV2Factory = "0xc35DADB65012eC5796536bD9864eD8773aBc74C4";
const sushiswapV2Router = "0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506";
const sushiMiniChefV2 = "0x0769fd68dFb93167989C6f7254cd0D766Fb2841F";

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

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

const sushiLpUsdcWeth = "0x34965ba0ac2451A34a0471F04CCa3F990b8dea27";
const sushiLPUsdcWethPoolId = 1;

describe("Sushiswap V2 Test", function () {
  let WMatic, WETH, USDC, USDT, SushiLPUSDCWETH, SUSHI;
  let sushiLPAggregator, sushiMiniChefV2Guard;
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

    // Deploy Sushi LP Aggregator
    const SushiLPAggregator = await ethers.getContractFactory("SushiLPAggregator");
    sushiLPAggregator = await SushiLPAggregator.deploy(sushiLpUsdcWeth, usdc_price_feed, eth_price_feed);
    // Initialize Asset Price Consumer
    const assetWmatic = { asset: wmatic, assetType: 0, aggregator: matic_price_feed };
    const assetWeth = { asset: weth, assetType: 0, aggregator: eth_price_feed };
    const assetUsdt = { asset: usdt, assetType: 0, aggregator: usdt_price_feed };
    const assetUsdc = { asset: usdc, assetType: 0, aggregator: usdc_price_feed };
    const assetSushi = { asset: sushiToken, assetType: 0, aggregator: sushi_price_feed };
    const assetSushiLPWethUsdc = { asset: sushiLpUsdcWeth, assetType: 2, aggregator: sushiLPAggregator.address };
    const assetHandlerInitAssets = [assetWmatic, assetWeth, assetUsdt, assetUsdc, assetSushi, assetSushiLPWethUsdc];

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

    const UniswapV2RouterGuard = await ethers.getContractFactory("UniswapV2RouterGuard");
    uniswapV2RouterGuard = await UniswapV2RouterGuard.deploy(sushiswapV2Factory);
    uniswapV2RouterGuard.deployed();

    const SushiMiniChefV2Guard = await ethers.getContractFactory("SushiMiniChefV2Guard");
    sushiMiniChefV2Guard = await SushiMiniChefV2Guard.deploy(sushiToken, wmatic);
    sushiMiniChefV2Guard.deployed();

    const SushiLPAssetGuard = await ethers.getContractFactory("SushiLPAssetGuard");
    sushiLPAssetGuard = await SushiLPAssetGuard.deploy(sushiMiniChefV2, [[sushiLpUsdcWeth, sushiLPUsdcWethPoolId]]); // initialise with Sushi staking pool Id
    sushiLPAssetGuard.deployed();

    await governance.setAssetGuard(0, erc20Guard.address);
    await governance.setAssetGuard(2, sushiLPAssetGuard.address);
    await governance.setContractGuard(sushiswapV2Router, uniswapV2RouterGuard.address);
    await governance.setContractGuard(sushiMiniChefV2, sushiMiniChefV2Guard.address);
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
    await poolLogic.initialize(poolFactory.address, false, "Test Fund", "DHTF");

    console.log("Passed poolLogic Init!");

    await poolManagerLogic.initialize(poolFactory.address, manager.address, "Barren Wuffet", poolLogic.address, [
      [usdc, true],
      [weth, true],
    ]);

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
    ).to.be.revertedWith("invalid fraction");

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
    checkAlmostSame(event.totalInvestorFundTokens, units(200));
    checkAlmostSame(event.fundValue, units(200));
    checkAlmostSame(event.totalSupply, units(200));
  });

  it("Should be able to approve", async () => {
    const IERC20 = await hre.artifacts.readArtifact("IERC20");
    const iERC20 = new ethers.utils.Interface(IERC20.abi);
    let approveABI = iERC20.encodeFunctionData("approve", [usdc, (200e6).toString()]);
    await expect(poolLogicProxy.connect(manager).execTransaction(usdt, approveABI)).to.be.revertedWith(
      "asset not enabled in pool",
    );

    await expect(poolLogicProxy.connect(manager).execTransaction(usdc, approveABI)).to.be.revertedWith(
      "unsupported spender approval",
    );

    approveABI = iERC20.encodeFunctionData("approve", [sushiswapV2Router, (200e6).toString()]);
    await poolLogicProxy.connect(manager).execTransaction(usdc, approveABI);
  });

  it("should be able to swap tokens on sushiswap.", async () => {
    let exchangeEvent = new Promise((resolve, reject) => {
      uniswapV2RouterGuard.on(
        "Exchange",
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
      [usdc, weth],
      poolManagerLogicProxy.address,
      0,
    ]);

    await expect(
      poolLogicProxy.connect(manager).execTransaction("0x0000000000000000000000000000000000000000", swapABI),
    ).to.be.revertedWith("non-zero address is required");

    swapABI = iSushiswapV2Router.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      0,
      [usdt, weth],
      poolLogicProxy.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(usdc, swapABI)).to.be.revertedWith(
      "invalid transaction",
    );

    swapABI = iSushiswapV2Router.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      0,
      [usdt, weth],
      poolLogicProxy.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(sushiswapV2Router, swapABI)).to.be.revertedWith(
      "unsupported source asset",
    );

    swapABI = iSushiswapV2Router.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      0,
      [usdc, user.address, weth],
      poolLogicProxy.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(sushiswapV2Router, swapABI)).to.be.revertedWith(
      "invalid routing asset",
    );

    swapABI = iSushiswapV2Router.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      0,
      [usdc, weth, usdt],
      poolLogicProxy.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(sushiswapV2Router, swapABI)).to.be.revertedWith(
      "unsupported destination asset",
    );

    swapABI = iSushiswapV2Router.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      0,
      [usdc, weth],
      user.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(sushiswapV2Router, swapABI)).to.be.revertedWith(
      "recipient is not pool",
    );

    swapABI = iSushiswapV2Router.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      0,
      [usdc, weth],
      poolLogicProxy.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(sushiswapV2Router, swapABI)).to.be.revertedWith(
      "failed to execute the call",
    );

    swapABI = iSushiswapV2Router.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      0,
      [usdc, weth],
      poolLogicProxy.address,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);
    await poolLogicProxy.connect(manager).execTransaction(sushiswapV2Router, swapABI);

    expect(await USDC.balanceOf(poolLogicProxy.address)).to.be.equal(100e6);

    let event = await exchangeEvent;
    expect(event.sourceAsset).to.equal(usdc);
    expect(event.sourceAmount).to.equal((100e6).toString());
    expect(event.destinationAsset).to.equal(weth);
  });

  it("should be able to withdraw", async function () {
    let withdrawalEvent = new Promise((resolve, reject) => {
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
    let withdrawAmount = units(100);

    await expect(poolLogicProxy.withdraw(withdrawAmount)).to.be.revertedWith("cooldown active");

    await poolFactory.setExitCooldown(0);

    await poolLogicProxy.withdraw(withdrawAmount);

    let event = await withdrawalEvent;
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
        sushiLPUsdcWethPoolId,
        availableLpToken,
        poolLogicProxy.address,
      ]);

      const IERC20 = await hre.artifacts.readArtifact("IERC20");
      const iERC20 = new ethers.utils.Interface(IERC20.abi);
      let approveABI = iERC20.encodeFunctionData("approve", [sushiMiniChefV2, availableLpToken]);
      await poolLogicProxy.connect(manager).execTransaction(sushiLpUsdcWeth, approveABI);
      await poolLogicProxy.connect(manager).execTransaction(sushiMiniChefV2, depositAbi);
    };

    it("manager can add liquidity", async () => {
      await poolManagerLogicProxy.connect(manager).changeAssets([[sushiLpUsdcWeth, false]], []);

      const tokenA = usdc;
      const tokenB = weth;
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
      let approveABI = iERC20.encodeFunctionData("approve", [sushiswapV2Router, amountADesired]);
      await poolLogicProxy.connect(manager).execTransaction(usdc, approveABI);
      approveABI = iERC20.encodeFunctionData("approve", [sushiswapV2Router, amountBDesired]);
      await poolLogicProxy.connect(manager).execTransaction(weth, approveABI);

      const lpBalanceBefore = await SushiLPUSDCWETH.balanceOf(poolLogicProxy.address);
      const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
      const wethBalanceBefore = await WETH.balanceOf(poolLogicProxy.address);
      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      expect(lpBalanceBefore).to.be.equal(0);

      await poolLogicProxy.connect(manager).execTransaction(sushiswapV2Router, addLiquidityAbi);

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
        sushiLPUsdcWethPoolId,
        availableLpToken,
        poolLogicProxy.address,
      ]);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      const sushiLPPrice = await assetHandler.getUSDPrice(sushiLpUsdcWeth);
      expect(totalFundValueBefore).to.gte(
        sushiLPPrice.mul(availableLpToken).div(ethers.BigNumber.from((1e18).toString())),
      ); // should at least account for the staked tokens

      // attempt to deposit with manager as recipient
      const badDepositAbi = iMiniChefV2.encodeFunctionData("deposit", [
        sushiLPUsdcWethPoolId,
        availableLpToken,
        manager.address,
      ]);

      await expect(poolLogicProxy.connect(manager).execTransaction(sushiMiniChefV2, badDepositAbi)).to.be.revertedWith(
        "recipient is not pool",
      );

      const IERC20 = await hre.artifacts.readArtifact("IERC20");
      const iERC20 = new ethers.utils.Interface(IERC20.abi);
      let approveABI = iERC20.encodeFunctionData("approve", [sushiMiniChefV2, availableLpToken]);
      await poolLogicProxy.connect(manager).execTransaction(sushiLpUsdcWeth, approveABI);

      await poolLogicProxy.connect(manager).execTransaction(sushiMiniChefV2, depositAbi);

      expect(await poolManagerLogicProxy.assetBalance(sushiLpUsdcWeth)).to.be.equal(availableLpToken);
      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);

      const event = await stakeEvent;
      expect(event.fundAddress).to.equal(poolLogicProxy.address);
      expect(event.asset).to.equal(sushiLpUsdcWeth);
      expect(event.stakingContract).to.equal(sushiMiniChefV2);
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
        sushiLPUsdcWethPoolId,
        availableLpToken,
        manager.address,
      ]);

      await expect(poolLogicProxy.connect(manager).execTransaction(sushiMiniChefV2, badWithdrawAbi)).to.be.revertedWith(
        "recipient is not pool",
      );

      const withdrawAbi = iMiniChefV2.encodeFunctionData("withdraw", [
        sushiLPUsdcWethPoolId,
        availableLpToken,
        poolLogicProxy.address,
      ]);

      const wmaticBalanceBefore = await WMATIC.balanceOf(poolLogicProxy.address);
      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      await poolLogicProxy.connect(manager).execTransaction(sushiMiniChefV2, withdrawAbi);

      expect(await poolManagerLogicProxy.assetBalance(sushiLpUsdcWeth)).to.be.equal(availableLpToken);
      expect(await WMATIC.balanceOf(poolLogicProxy.address)).to.be.gt(wmaticBalanceBefore);
      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);

      const event = await unstakeEvent;
      expect(event.fundAddress).to.equal(poolLogicProxy.address);
      expect(event.asset).to.equal(sushiLpUsdcWeth);
      expect(event.stakingContract).to.equal(sushiMiniChefV2);
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

      const harvestAbi = iMiniChefV2.encodeFunctionData("harvest", [sushiLPUsdcWethPoolId, poolLogicProxy.address]);

      await expect(poolLogicProxy.connect(manager).execTransaction(sushiMiniChefV2, harvestAbi)).to.be.revertedWith(
        "enable reward token",
      );

      // enable SUSHI token in pool
      await poolManagerLogicProxy.connect(manager).changeAssets([[sushiToken, false]], []);

      await expect(poolLogicProxy.connect(manager).execTransaction(sushiMiniChefV2, harvestAbi)).to.be.revertedWith(
        "enable reward token",
      );

      // enable WMATIC token in pool
      await poolManagerLogicProxy.connect(manager).changeAssets([[wmatic, false]], []);

      // attempt to harvest with manager as recipient
      const badHarvestAbi = iMiniChefV2.encodeFunctionData("withdraw", [
        sushiLPUsdcWethPoolId,
        availableLpToken,
        manager.address,
      ]);

      await expect(poolLogicProxy.connect(manager).execTransaction(sushiMiniChefV2, badHarvestAbi)).to.be.revertedWith(
        "recipient is not pool",
      );

      expect(await SUSHI.balanceOf(poolLogicProxy.address)).to.be.equal(0);

      await poolLogicProxy.connect(manager).execTransaction(sushiMiniChefV2, harvestAbi);

      const event = await claimEvent;
      expect(event.fundAddress).to.equal(poolLogicProxy.address);
      expect(event.stakingContract).to.equal(sushiMiniChefV2);

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
        sushiLPUsdcWethPoolId,
        availableLpToken,
        manager.address,
      ]);

      await expect(
        poolLogicProxy.connect(manager).execTransaction(sushiMiniChefV2, badWithdrawAndHarvestAbi),
      ).to.be.revertedWith("recipient is not pool");

      // manager attempts to withdraw unknown LP token
      badWithdrawAndHarvestAbi = iMiniChefV2.encodeFunctionData("withdrawAndHarvest", [
        0,
        availableLpToken,
        poolLogicProxy.address,
      ]);

      await expect(
        poolLogicProxy.connect(manager).execTransaction(sushiMiniChefV2, badWithdrawAndHarvestAbi),
      ).to.be.revertedWith("unsupported lp asset");

      const withdrawAndHarvestAbi = iMiniChefV2.encodeFunctionData("withdrawAndHarvest", [
        sushiLPUsdcWethPoolId,
        availableLpToken,
        poolLogicProxy.address,
      ]);

      const sushiBalanceBefore = await SUSHI.balanceOf(poolLogicProxy.address);
      const wmaticBalanceBefore = await WMATIC.balanceOf(poolLogicProxy.address);
      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      await ethers.provider.send("evm_increaseTime", [3600 * 24]);
      await poolLogicProxy.connect(manager).execTransaction(sushiMiniChefV2, withdrawAndHarvestAbi);

      expect(await SUSHI.balanceOf(poolLogicProxy.address)).to.be.gt(sushiBalanceBefore);
      expect(await WMATIC.balanceOf(poolLogicProxy.address)).to.be.gt(wmaticBalanceBefore);
      expect(await poolManagerLogicProxy.totalFundValue()).to.be.gt(totalFundValueBefore);

      const eventUnstake = await unstakeEvent;
      expect(eventUnstake.fundAddress).to.equal(poolLogicProxy.address);
      expect(eventUnstake.asset).to.equal(sushiLpUsdcWeth);
      expect(eventUnstake.stakingContract).to.equal(sushiMiniChefV2);
      expect(eventUnstake.amount).to.equal(availableLpToken);

      const eventClaim = await claimEvent;
      expect(eventClaim.fundAddress).to.equal(poolLogicProxy.address);
      expect(eventClaim.stakingContract).to.equal(sushiMiniChefV2);
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
      await poolManagerLogicProxy.connect(manager).setManagerFeeNumerator("0");

      const totalSupply = await poolLogicProxy.totalSupply();

      const totalFundValue = await poolManagerLogicProxy.totalFundValue();
      const usdcBalance = await USDC.balanceOf(poolLogicProxy.address);
      const wethBalance = await WETH.balanceOf(poolLogicProxy.address);
      const usdcPrice = await assetHandler.getUSDPrice(usdc);
      const wethPrice = await assetHandler.getUSDPrice(weth);
      const sushiLPPrice = await assetHandler.getUSDPrice(sushiLpUsdcWeth);
      const expectedFundValue = usdcBalance
        .mul(usdcPrice)
        .div(ethers.BigNumber.from("1000000"))
        .add(wethBalance.mul(wethPrice).div(units(1)))
        .add(availableLpToken.mul(sushiLPPrice).div(units(1)));

      checkAlmostSame(totalFundValue, expectedFundValue.toString());

      // Withdraw all
      const withdrawAmount = units(100);
      const investorFundBalance = await poolLogicProxy.balanceOf(logicOwner.address);

      const sushiBalanceBefore = await SUSHI.balanceOf(logicOwner.address);
      const wmaticBalanceBefore = await WMATIC.balanceOf(logicOwner.address);
      const lpBalanceBefore = await SushiLPUSDCWETH.balanceOf(logicOwner.address);

      ethers.provider.send("evm_increaseTime", [3600 * 24]); // add 1 day to avoid cooldown revert
      await poolLogicProxy.withdraw(withdrawAmount);

      const eventWithdrawal = await withdrawalEvent;

      const valueWithdrawn = withdrawAmount.mul(totalFundValue).div(totalSupply);
      const expectedWithdrawAmount = availableLpToken
        .mul(ethers.BigNumber.from(withdrawAmount))
        .div(ethers.BigNumber.from(totalSupply));
      const expectedFundValueAfter = totalFundValue.sub(valueWithdrawn);

      expect(await SUSHI.balanceOf(logicOwner.address)).to.be.gt(sushiBalanceBefore);
      expect(await WMATIC.balanceOf(logicOwner.address)).to.be.gt(wmaticBalanceBefore);
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
