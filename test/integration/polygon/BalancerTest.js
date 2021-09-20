const { ethers, upgrades } = require("hardhat");
const { expect, use } = require("chai");
const chaiAlmost = require("chai-almost");
const axios = require("axios");
const { checkAlmostSame, toBytes32, getAmountOut, getAmountIn, units } = require("../../TestHelpers");

use(chaiAlmost());

const balancerV2Vault = "0xBA12222222228d8Ba445958a75a0704d566BF2C8";
const quickswapRouter = "0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff";

// For mainnet
const wmatic = "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270";
const weth = "0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619";
const usdc = "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174";
const usdt = "0xc2132D05D31c914a87C6611C10748AEb04B58e8F";
const dai = "0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063";
const matic_price_feed = "0xAB594600376Ec9fD91F8e885dADF0CE036862dE0";
const eth_price_feed = "0xF9680D99D6C9589e2a93a78A04A279e509205945";
const usdc_price_feed = "0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7";
const usdt_price_feed = "0x0A6513e40db6EB1b165753AD52E80663aeA50545";

const quickLpUsdcUsdt = "0x2cf7252e74036d1da831d11089d326296e64a728";

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

describe("Balancer V2 Test", function () {
  let WMatic, WETH, USDC, USDT;
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

    // Initialize Asset Price Consumer
    const assetWeth = { asset: weth, assetType: 0, aggregator: eth_price_feed };
    const assetUsdt = { asset: usdt, assetType: 0, aggregator: usdt_price_feed };
    const assetUsdc = { asset: usdc, assetType: 0, aggregator: usdc_price_feed };
    const assetHandlerInitAssets = [assetWeth, assetUsdt, assetUsdc];

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
    await erc20Guard.deployed();

    const OpenAssetGuard = await ethers.getContractFactory("OpenAssetGuard");
    openAssetGuard = await OpenAssetGuard.deploy([wmatic]);
    await openAssetGuard.deployed();

    const UniswapV2RouterGuard = await ethers.getContractFactory("UniswapV2RouterGuard");
    uniswapV2RouterGuard = await UniswapV2RouterGuard.deploy(2, 100); // set slippage 2% for testing
    await uniswapV2RouterGuard.deployed();

    const BalancerV2Guard = await ethers.getContractFactory("BalancerV2Guard");
    balancerV2Guard = await BalancerV2Guard.deploy(2, 100); // set slippage 2%
    balancerV2Guard.deployed();

    await governance.setAssetGuard(0, erc20Guard.address);
    await governance.setContractGuard(quickswapRouter, uniswapV2RouterGuard.address);
    await governance.setContractGuard(balancerV2Vault, balancerV2Guard.address);
    await governance.setAddresses([[toBytes32("openAssetGuard"), openAssetGuard.address]]);

    await poolFactory.setExitFee(5, 1000); // 0.5%
  });

  it("Should be able to get USDC", async function () {
    const IWETH = await hre.artifacts.readArtifact("IWETH");
    WMatic = await ethers.getContractAt(IWETH.abi, wmatic);
    const IERC20 = await hre.artifacts.readArtifact("IERC20");
    USDT = await ethers.getContractAt(IERC20.abi, usdt);
    USDC = await ethers.getContractAt(IERC20.abi, usdc);
    WETH = await ethers.getContractAt(IERC20.abi, weth);
    WMATIC = await ethers.getContractAt(IERC20.abi, wmatic);
    let balance = await ethers.provider.getBalance(logicOwner.address);
    console.log("Matic balance: ", balance.toString());
    balance = await WMATIC.balanceOf(logicOwner.address);
    console.log("WMatic balance: ", balance.toString());
    const IUniswapV2Router = await hre.artifacts.readArtifact("IUniswapV2Router");
    const QuickSwapRouter = await ethers.getContractAt(IUniswapV2Router.abi, quickswapRouter);
    // deposit Matic -> WMatic
    await WMatic.deposit({ value: units(500) });
    balance = await WMATIC.balanceOf(logicOwner.address);
    console.log("WMatic balance: ", balance.toString());
    // WMatic -> USDC
    await WMatic.approve(quickswapRouter, units(500));
    await QuickSwapRouter.swapExactTokensForTokens(
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
        [usdt, true],
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
    expect(await poolManagerLogicProxy.isSupportedAsset(usdt)).to.be.true;

    //Other assets are not supported
    expect(await poolManagerLogicProxy.isSupportedAsset(wmatic)).to.be.false;
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

    await expect(poolLogicProxy.deposit(wmatic, (200e6).toString())).to.be.revertedWith("invalid deposit asset");

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
    await expect(poolLogicProxy.connect(manager).execTransaction(weth, approveABI)).to.be.revertedWith(
      "asset not enabled in pool",
    );

    await expect(poolLogicProxy.connect(manager).execTransaction(usdc, approveABI)).to.be.revertedWith(
      "unsupported spender approval",
    );

    approveABI = iERC20.encodeFunctionData("approve", [balancerV2Vault, (200e6).toString()]);
    await poolLogicProxy.connect(manager).execTransaction(usdc, approveABI);
  });

  it("should be able to swap tokens on balancer - swap exactInput.", async () => {
    const poolId = "0x06df3b2bbb68adc8b0e302443692037ed9f91b42000000000000000000000012";
    const kind = 0;
    const assetIn = usdc;
    const assetOut = usdt;
    const amount = units(1, 6);
    const sender = poolLogicProxy.address;
    const recipient = poolLogicProxy.address;
    const limit = "990000";

    const IBalancerV2Vault = await hre.artifacts.readArtifact("IBalancerV2Vault");
    const iBalancerV2Vault = new ethers.utils.Interface(IBalancerV2Vault.abi);

    let swapTx = iBalancerV2Vault.encodeFunctionData("swap", [
      [poolId, kind, assetIn, dai, amount, "0x"],
      [sender, false, recipient, false],
      limit,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);

    await expect(poolLogicProxy.connect(manager).execTransaction(balancerV2Vault, swapTx)).to.be.revertedWith(
      "unsupported destination asset",
    );

    swapTx = iBalancerV2Vault.encodeFunctionData("swap", [
      [poolId, kind, assetIn, assetOut, amount, "0x"],
      [dai, false, recipient, false],
      limit,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);

    await expect(poolLogicProxy.connect(manager).execTransaction(balancerV2Vault, swapTx)).to.be.revertedWith(
      "sender is not pool",
    );

    swapTx = iBalancerV2Vault.encodeFunctionData("swap", [
      [poolId, kind, assetIn, assetOut, amount, "0x"],
      [sender, false, dai, false],
      limit,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);

    await expect(poolLogicProxy.connect(manager).execTransaction(balancerV2Vault, swapTx)).to.be.revertedWith(
      "recipient is not pool",
    );

    swapTx = iBalancerV2Vault.encodeFunctionData("swap", [
      [poolId, kind, assetIn, assetOut, amount, "0x"],
      [sender, false, recipient, false],
      "950000",
      Math.floor(Date.now() / 1000 + 100000000),
    ]);

    await expect(poolLogicProxy.connect(manager).execTransaction(balancerV2Vault, swapTx)).to.be.revertedWith(
      "slippage limit exceed",
    );

    swapTx = iBalancerV2Vault.encodeFunctionData("swap", [
      [poolId, kind, assetIn, assetOut, amount, "0x"],
      [sender, false, recipient, false],
      limit,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);

    const usdtBalanceBefore = ethers.BigNumber.from(await USDT.balanceOf(poolLogicProxy.address));
    const usdcBalanceBefore = ethers.BigNumber.from(await USDC.balanceOf(poolLogicProxy.address));

    await poolLogicProxy.connect(manager).execTransaction(balancerV2Vault, swapTx);

    const usdtBalanceAfter = await USDT.balanceOf(poolLogicProxy.address);
    const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
    expect(usdcBalanceAfter).to.equal(usdcBalanceBefore.sub(amount));
    checkAlmostSame(usdtBalanceAfter, usdtBalanceBefore.add(amount));
  });

  it("should be able to swap tokens on balancer - swap exactOutput.", async () => {
    const poolId = "0x06df3b2bbb68adc8b0e302443692037ed9f91b42000000000000000000000012";
    const kind = 1;
    const assetIn = usdc;
    const assetOut = usdt;
    const amount = units(1, 6);
    const sender = poolLogicProxy.address;
    const recipient = poolLogicProxy.address;
    const limit = "1010000";

    const IBalancerV2Vault = await hre.artifacts.readArtifact("IBalancerV2Vault");
    const iBalancerV2Vault = new ethers.utils.Interface(IBalancerV2Vault.abi);

    let swapTx = iBalancerV2Vault.encodeFunctionData("swap", [
      [poolId, kind, assetIn, dai, amount, "0x"],
      [sender, false, recipient, false],
      limit,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);

    await expect(poolLogicProxy.connect(manager).execTransaction(balancerV2Vault, swapTx)).to.be.revertedWith(
      "unsupported destination asset",
    );

    swapTx = iBalancerV2Vault.encodeFunctionData("swap", [
      [poolId, kind, assetIn, assetOut, amount, "0x"],
      [dai, false, recipient, false],
      limit,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);

    await expect(poolLogicProxy.connect(manager).execTransaction(balancerV2Vault, swapTx)).to.be.revertedWith(
      "sender is not pool",
    );

    swapTx = iBalancerV2Vault.encodeFunctionData("swap", [
      [poolId, kind, assetIn, assetOut, amount, "0x"],
      [sender, false, dai, false],
      limit,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);

    await expect(poolLogicProxy.connect(manager).execTransaction(balancerV2Vault, swapTx)).to.be.revertedWith(
      "recipient is not pool",
    );

    swapTx = iBalancerV2Vault.encodeFunctionData("swap", [
      [poolId, kind, assetIn, assetOut, amount, "0x"],
      [sender, false, recipient, false],
      "1050000",
      Math.floor(Date.now() / 1000 + 100000000),
    ]);

    await expect(poolLogicProxy.connect(manager).execTransaction(balancerV2Vault, swapTx)).to.be.revertedWith(
      "slippage limit exceed",
    );

    swapTx = iBalancerV2Vault.encodeFunctionData("swap", [
      [poolId, kind, assetIn, assetOut, amount, "0x"],
      [sender, false, recipient, false],
      limit,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);

    const usdtBalanceBefore = ethers.BigNumber.from(await USDT.balanceOf(poolLogicProxy.address));
    const usdcBalanceBefore = ethers.BigNumber.from(await USDC.balanceOf(poolLogicProxy.address));

    await poolLogicProxy.connect(manager).execTransaction(balancerV2Vault, swapTx);

    const usdtBalanceAfter = await USDT.balanceOf(poolLogicProxy.address);
    const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
    checkAlmostSame(usdcBalanceAfter, usdcBalanceBefore.sub(amount));
    expect(usdtBalanceAfter).to.equal(usdtBalanceBefore.add(amount));
  });

  it("should be able to swap tokens on balancer - batchSwap exactInput.", async () => {
    const kind = 0;
    const amount = units(1, 6);
    const pools = [
      ["0x06df3b2bbb68adc8b0e302443692037ed9f91b42000000000000000000000012", 0, 1, "500000", "0x"],
      ["0x06df3b2bbb68adc8b0e302443692037ed9f91b42000000000000000000000012", 0, 1, "500000", "0x"],
    ];
    const assets = [usdc, usdt];
    const sender = poolLogicProxy.address;
    const recipient = poolLogicProxy.address;
    const limits = ["1000000", "-990000"];

    const IBalancerV2Vault = await hre.artifacts.readArtifact("IBalancerV2Vault");
    const iBalancerV2Vault = new ethers.utils.Interface(IBalancerV2Vault.abi);

    let swapTx = iBalancerV2Vault.encodeFunctionData("batchSwap", [
      kind,
      pools,
      assets,
      [sender, false, recipient, false],
      limits,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);

    const usdtBalanceBefore = ethers.BigNumber.from(await USDT.balanceOf(poolLogicProxy.address));
    const usdcBalanceBefore = ethers.BigNumber.from(await USDC.balanceOf(poolLogicProxy.address));

    await poolLogicProxy.connect(manager).execTransaction(balancerV2Vault, swapTx);

    const usdtBalanceAfter = await USDT.balanceOf(poolLogicProxy.address);
    const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
    expect(usdcBalanceAfter).to.equal(usdcBalanceBefore.sub(amount));
    checkAlmostSame(usdtBalanceAfter, usdtBalanceBefore.add(amount));
  });

  it("should be able to swap tokens on balancer - batchSwap exactOutput.", async () => {
    const kind = 1;
    const amount = units(1, 6);
    const pools = [
      ["0x06df3b2bbb68adc8b0e302443692037ed9f91b42000000000000000000000012", 0, 1, "500000", "0x"],
      ["0x06df3b2bbb68adc8b0e302443692037ed9f91b42000000000000000000000012", 0, 1, "500000", "0x"],
    ];
    const assets = [usdc, usdt];
    const sender = poolLogicProxy.address;
    const recipient = poolLogicProxy.address;
    const limits = ["1010000", "-1000000"];

    const IBalancerV2Vault = await hre.artifacts.readArtifact("IBalancerV2Vault");
    const iBalancerV2Vault = new ethers.utils.Interface(IBalancerV2Vault.abi);

    let swapTx = iBalancerV2Vault.encodeFunctionData("batchSwap", [
      kind,
      pools,
      assets,
      [sender, false, recipient, false],
      limits,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);

    const usdtBalanceBefore = ethers.BigNumber.from(await USDT.balanceOf(poolLogicProxy.address));
    const usdcBalanceBefore = ethers.BigNumber.from(await USDC.balanceOf(poolLogicProxy.address));

    await poolLogicProxy.connect(manager).execTransaction(balancerV2Vault, swapTx);

    const usdtBalanceAfter = await USDT.balanceOf(poolLogicProxy.address);
    const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
    checkAlmostSame(usdcBalanceAfter, usdcBalanceBefore.sub(amount));
    expect(usdtBalanceAfter).to.equal(usdtBalanceBefore.add(amount));
  });
});
