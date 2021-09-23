const { ethers, upgrades } = require("hardhat");
const { expect, use } = require("chai");
const Decimal = require("decimal.js");
const chaiAlmost = require("chai-almost");
const { checkAlmostSame, toBytes32, units } = require("../../TestHelpers");
const { aave, balancer, quickswap, assets, price_feeds } = require("../polygon-data");

use(chaiAlmost());

// For mainnet

// balancer stable pool with USDC, DAI, miMatic, USDT
const balancer_stable_pool_info = {
  pool: "0x06df3b2bbb68adc8b0e302443692037ed9f91b42",
  poolId: "0x06df3b2bbb68adc8b0e302443692037ed9f91b42000000000000000000000012",
  tokens: [
    "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174",
    "0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063",
    "0xa3Fa99A148fA48D14Ed51d610c367C61876997F1",
    "0xc2132D05D31c914a87C6611C10748AEb04B58e8F",
  ],
  decimals: [6, 18, 18, 6],
  weights: [0.25, 0.25, 0.25, 0.25],
};

// balancer weighted pool with WETH, BALANCER
const balancer80_weth20_pool_info = {
  pool: "0x7EB878107Af0440F9E776f999CE053D277c8Aca8",
  poolId: "0x7eb878107af0440f9e776f999ce053d277c8aca800020000000000000000002f",
  tokens: ["0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619", "0x9a71012B13CA4d3D0Cdc72A177DF3ef03b0E76A3"],
  decimals: [18, 18],
  weights: [0.2, 0.8],
};
/*
1. 0x0297e37f1873d2dab4487aa67cd56b58e2f27875, 0x0297e37f1873d2dab4487aa67cd56b58e2f27875000100000000000000000002 - WMATIC, USDC, WETH, BALANCER
0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270,0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174,0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619,0x9a71012B13CA4d3D0Cdc72A177DF3ef03b0E76A3
2. 0x06df3b2bbb68adc8b0e302443692037ed9f91b42, 0x06df3b2bbb68adc8b0e302443692037ed9f91b42000000000000000000000012 - USDC, DAI, miMatic, USDT
0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174,0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,0xa3Fa99A148fA48D14Ed51d610c367C61876997F1,0xc2132D05D31c914a87C6611C10748AEb04B58e8F
*/

describe("Balancer V2 Test", function () {
  let WMatic, WETH, USDC, USDT, BALANCERLP_STABLE, BALANCER, BALANCERLP_WETH_BALANCER;
  let logicOwner, manager, dao;
  let PoolFactory, PoolLogic, PoolManagerLogic;
  let poolFactory, poolLogic, poolManagerLogic, poolLogicProxy, poolManagerLogicProxy, fundAddress;

  const deployBalancerV2LpAggregator = async (info) => {
    const ether = "1000000000000000000";
    const divisor = info.weights.reduce((acc, w, i) => {
      if (i == 0) {
        return new Decimal(w).pow(w);
      }
      return acc.mul(new Decimal(w).pow(w));
    }, new Decimal("0"));

    const K = new Decimal(ether).div(divisor).toFixed(0);

    let matrix = [];
    for (let i = 1; i <= 20; i++) {
      const elements = [new Decimal(10).pow(i).times(ether).toFixed(0)];
      for (let j = 0; j < info.weights.length; j++) {
        elements.push(new Decimal(10).pow(i).pow(info.weights[j]).times(ether).toFixed(0));
      }
      matrix.push(elements);
    }

    const BalancerV2LPAggregator = await ethers.getContractFactory("BalancerV2LPAggregator");
    return await BalancerV2LPAggregator.deploy(
      poolFactory.address,
      balancer.v2Vault,
      info.pool,
      info.tokens,
      info.decimals,
      info.weights.map((w) =>
        ethers.BigNumber.from(10)
          .pow(10)
          .mul(w * 100000000),
      ),
      [
        "50000000000000000", // maxPriceDeviation: 0.05
        K,
        "100000000", // powerPrecision
        matrix, // approximationMatrix
      ],
    );
  };

  before(async function () {
    [logicOwner, manager, dao, user] = await ethers.getSigners();

    const AssetHandlerLogic = await ethers.getContractFactory("AssetHandler");

    const Governance = await ethers.getContractFactory("Governance");
    let governance = await Governance.deploy();
    console.log("governance deployed to:", governance.address);

    const PoolPerformance = await ethers.getContractFactory("PoolPerformance");
    const poolPerformance = await upgrades.deployProxy(PoolPerformance, [aave.protocolDataProvider]);
    await poolPerformance.deployed();

    PoolLogic = await ethers.getContractFactory("PoolLogic");
    poolLogic = await PoolLogic.deploy();

    PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
    poolManagerLogic = await PoolManagerLogic.deploy();

    // Initialize Asset Price Consumer
    const assetWMatic = { asset: assets.wmatic, assetType: 0, aggregator: price_feeds.matic };
    const assetWeth = { asset: assets.weth, assetType: 0, aggregator: price_feeds.eth };
    const assetUsdt = { asset: assets.usdt, assetType: 0, aggregator: price_feeds.usdt };
    const assetUsdc = { asset: assets.usdc, assetType: 0, aggregator: price_feeds.usdc };
    const assetDai = { asset: assets.dai, assetType: 0, aggregator: price_feeds.dai };
    const assetBalancer = { asset: assets.balancer, assetType: 0, aggregator: price_feeds.balancer };
    const assetMiMatic = { asset: assets.miMatic, assetType: 0, aggregator: price_feeds.dai };
    const assetHandlerInitAssets = [
      assetWMatic,
      assetWeth,
      assetUsdt,
      assetUsdc,
      assetDai,
      assetBalancer,
      assetMiMatic,
    ];

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

    await poolFactory.setPoolPerformanceAddress(poolPerformance.address);
    // Deploy Balancer LP Aggregator
    const balancerV2Aggregator = await deployBalancerV2LpAggregator(balancer_stable_pool_info);
    const balancerLpAsset = {
      asset: balancer_stable_pool_info.pool,
      assetType: 6,
      aggregator: balancerV2Aggregator.address,
    };
    await assetHandler.addAssets([balancerLpAsset]);

    const balancerV2AggregatorWethBalancer = await deployBalancerV2LpAggregator(balancer80_weth20_pool_info);
    const balancerLpAssetWethBalancer = {
      asset: balancer80_weth20_pool_info.pool,
      assetType: 6,
      aggregator: balancerV2AggregatorWethBalancer.address,
    };
    await assetHandler.addAssets([balancerLpAssetWethBalancer]);

    const ERC20Guard = await ethers.getContractFactory("ERC20Guard");
    erc20Guard = await ERC20Guard.deploy();
    await erc20Guard.deployed();

    const OpenAssetGuard = await ethers.getContractFactory("OpenAssetGuard");
    openAssetGuard = await OpenAssetGuard.deploy([assets.wmatic]);
    await openAssetGuard.deployed();

    const UniswapV2RouterGuard = await ethers.getContractFactory("UniswapV2RouterGuard");
    uniswapV2RouterGuard = await UniswapV2RouterGuard.deploy(2, 100); // set slippage 2% for testing
    await uniswapV2RouterGuard.deployed();

    const BalancerV2Guard = await ethers.getContractFactory("BalancerV2Guard");
    balancerV2Guard = await BalancerV2Guard.deploy(2, 100); // set slippage 2%
    balancerV2Guard.deployed();

    await governance.setAssetGuard(0, erc20Guard.address);
    await governance.setAssetGuard(6, erc20Guard.address); // set balancer lp asset guard to normal erc20 guard
    await governance.setContractGuard(quickswap.router, uniswapV2RouterGuard.address);
    await governance.setContractGuard(balancer.v2Vault, balancerV2Guard.address);
    await governance.setAddresses([[toBytes32("openAssetGuard"), openAssetGuard.address]]);
  });

  it("Should be able to get USDC", async function () {
    const IWETH = await hre.artifacts.readArtifact("IWETH");
    WMatic = await ethers.getContractAt(IWETH.abi, assets.wmatic);
    const IERC20 = await hre.artifacts.readArtifact("IERC20");
    USDT = await ethers.getContractAt(IERC20.abi, assets.usdt);
    USDC = await ethers.getContractAt(IERC20.abi, assets.usdc);
    WETH = await ethers.getContractAt(IERC20.abi, assets.weth);
    WMATIC = await ethers.getContractAt(IERC20.abi, assets.wmatic);
    BALANCER = await ethers.getContractAt(IERC20.abi, assets.balancer);
    BALANCERLP_STABLE = await ethers.getContractAt(IERC20.abi, balancer_stable_pool_info.pool);
    BALANCERLP_WETH_BALANCER = await ethers.getContractAt(IERC20.abi, balancer80_weth20_pool_info.pool);
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
    await WMatic.approve(quickswap.router, units(500));
    await QuickSwapRouter.swapExactTokensForTokens(
      units(500),
      0,
      [assets.wmatic, assets.usdc],
      logicOwner.address,
      Math.floor(Date.now() / 1000 + 100000000),
    );
    balance = await USDC.balanceOf(logicOwner.address);
    console.log("USDC balance: ", balance.toString());
    // WMatic -> WETH
    await WMatic.approve(quickswap.router, units(500));
    await QuickSwapRouter.swapExactTokensForTokens(
      units(500),
      0,
      [assets.wmatic, assets.weth],
      logicOwner.address,
      Math.floor(Date.now() / 1000 + 100000000),
    );
    balance = await WETH.balanceOf(logicOwner.address);
    console.log("WETH balance: ", balance.toString());
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
          [assets.usdc, true],
          [assets.weth, true],
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
        [assets.usdc, true],
        [assets.usdt, true],
        [assets.weth, true],
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
    expect(numberOfSupportedAssets).to.eq(3);
    expect(await poolManagerLogicProxy.isSupportedAsset(assets.usdc)).to.be.true;
    expect(await poolManagerLogicProxy.isSupportedAsset(assets.usdt)).to.be.true;
    expect(await poolManagerLogicProxy.isSupportedAsset(assets.weth)).to.be.true;

    //Other assets are not supported
    expect(await poolManagerLogicProxy.isSupportedAsset(assets.wmatic)).to.be.false;
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

    let chainlinkEth = await ethers.getContractAt("AggregatorV3Interface", price_feeds.eth);
    let ethPrice = await chainlinkEth.latestRoundData();
    console.log("eth price: ", ethPrice[1].toString());
    console.log("updatedAt: ", ethPrice[3].toString());

    let chainlinkUsdc = await ethers.getContractAt("AggregatorV3Interface", price_feeds.usdc);
    let usdcPrice = await chainlinkUsdc.latestRoundData();
    console.log("usdc price: ", usdcPrice[1].toString());
    console.log("updatedAt: ", usdcPrice[3].toString());

    // Revert on second time
    let assetBalance = await poolManagerLogicProxy.assetBalance(assets.usdc);
    console.log("assetBalance: ", assetBalance.toString());

    // Revert on second time
    let assetValue = await poolManagerLogicProxy["assetValue(address)"](assets.usdc);
    console.log("assetValue: ", assetValue.toString());

    // Revert on second time
    totalFundValue = await poolManagerLogicProxy.totalFundValue();
    expect(totalFundValue.toString()).to.equal("0");

    await expect(poolLogicProxy.deposit(assets.wmatic, (200e6).toString())).to.be.revertedWith("invalid deposit asset");

    await USDC.approve(poolLogicProxy.address, (200e6).toString());
    await poolLogicProxy.deposit(assets.usdc, (200e6).toString());
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
    let approveABI = iERC20.encodeFunctionData("approve", [assets.usdc, (200e6).toString()]);
    await expect(poolLogicProxy.connect(manager).execTransaction(assets.balancer, approveABI)).to.be.revertedWith(
      "asset not enabled in pool",
    );

    await expect(poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI)).to.be.revertedWith(
      "unsupported spender approval",
    );

    approveABI = iERC20.encodeFunctionData("approve", [balancer.v2Vault, (200e6).toString()]);
    await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);
  });

  it("should be able to swap tokens on balancer - swap exactInput.", async () => {
    const poolId = "0x06df3b2bbb68adc8b0e302443692037ed9f91b42000000000000000000000012";
    const kind = 0;
    const assetIn = assets.usdc;
    const assetOut = assets.usdt;
    const amount = units(1, 6);
    const sender = poolLogicProxy.address;
    const recipient = poolLogicProxy.address;
    const limit = "990000";

    const IBalancerV2Vault = await hre.artifacts.readArtifact("IBalancerV2Vault");
    const iBalancerV2Vault = new ethers.utils.Interface(IBalancerV2Vault.abi);

    let swapTx = iBalancerV2Vault.encodeFunctionData("swap", [
      [poolId, kind, assetIn, assets.dai, amount, "0x"],
      [sender, false, recipient, false],
      limit,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);

    await expect(poolLogicProxy.connect(manager).execTransaction(balancer.v2Vault, swapTx)).to.be.revertedWith(
      "unsupported destination asset",
    );

    swapTx = iBalancerV2Vault.encodeFunctionData("swap", [
      [poolId, kind, assetIn, assetOut, amount, "0x"],
      [assets.dai, false, recipient, false],
      limit,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);

    await expect(poolLogicProxy.connect(manager).execTransaction(balancer.v2Vault, swapTx)).to.be.revertedWith(
      "sender is not pool",
    );

    swapTx = iBalancerV2Vault.encodeFunctionData("swap", [
      [poolId, kind, assetIn, assetOut, amount, "0x"],
      [sender, false, assets.dai, false],
      limit,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);

    await expect(poolLogicProxy.connect(manager).execTransaction(balancer.v2Vault, swapTx)).to.be.revertedWith(
      "recipient is not pool",
    );

    swapTx = iBalancerV2Vault.encodeFunctionData("swap", [
      [poolId, kind, assetIn, assetOut, amount, "0x"],
      [sender, false, recipient, false],
      "950000",
      Math.floor(Date.now() / 1000 + 100000000),
    ]);

    await expect(poolLogicProxy.connect(manager).execTransaction(balancer.v2Vault, swapTx)).to.be.revertedWith(
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
    const totalFundValueBefore = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());

    await poolLogicProxy.connect(manager).execTransaction(balancer.v2Vault, swapTx);

    const usdtBalanceAfter = await USDT.balanceOf(poolLogicProxy.address);
    const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
    expect(usdcBalanceAfter).to.equal(usdcBalanceBefore.sub(amount));
    checkAlmostSame(usdtBalanceAfter, usdtBalanceBefore.add(amount));

    const totalFundValueAfter = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());
    checkAlmostSame(totalFundValueBefore, totalFundValueAfter);
  });

  it("should be able to swap tokens on balancer - swap exactOutput.", async () => {
    const poolId = "0x06df3b2bbb68adc8b0e302443692037ed9f91b42000000000000000000000012";
    const kind = 1;
    const assetIn = assets.usdc;
    const assetOut = assets.usdt;
    const amount = units(1, 6);
    const sender = poolLogicProxy.address;
    const recipient = poolLogicProxy.address;
    const limit = "1010000";

    const IBalancerV2Vault = await hre.artifacts.readArtifact("IBalancerV2Vault");
    const iBalancerV2Vault = new ethers.utils.Interface(IBalancerV2Vault.abi);

    let swapTx = iBalancerV2Vault.encodeFunctionData("swap", [
      [poolId, kind, assetIn, assets.dai, amount, "0x"],
      [sender, false, recipient, false],
      limit,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);

    await expect(poolLogicProxy.connect(manager).execTransaction(balancer.v2Vault, swapTx)).to.be.revertedWith(
      "unsupported destination asset",
    );

    swapTx = iBalancerV2Vault.encodeFunctionData("swap", [
      [poolId, kind, assetIn, assetOut, amount, "0x"],
      [assets.dai, false, recipient, false],
      limit,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);

    await expect(poolLogicProxy.connect(manager).execTransaction(balancer.v2Vault, swapTx)).to.be.revertedWith(
      "sender is not pool",
    );

    swapTx = iBalancerV2Vault.encodeFunctionData("swap", [
      [poolId, kind, assetIn, assetOut, amount, "0x"],
      [sender, false, assets.dai, false],
      limit,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);

    await expect(poolLogicProxy.connect(manager).execTransaction(balancer.v2Vault, swapTx)).to.be.revertedWith(
      "recipient is not pool",
    );

    swapTx = iBalancerV2Vault.encodeFunctionData("swap", [
      [poolId, kind, assetIn, assetOut, amount, "0x"],
      [sender, false, recipient, false],
      "1050000",
      Math.floor(Date.now() / 1000 + 100000000),
    ]);

    await expect(poolLogicProxy.connect(manager).execTransaction(balancer.v2Vault, swapTx)).to.be.revertedWith(
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
    const totalFundValueBefore = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());

    await poolLogicProxy.connect(manager).execTransaction(balancer.v2Vault, swapTx);

    const usdtBalanceAfter = await USDT.balanceOf(poolLogicProxy.address);
    const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
    checkAlmostSame(usdcBalanceAfter, usdcBalanceBefore.sub(amount));
    expect(usdtBalanceAfter).to.equal(usdtBalanceBefore.add(amount));

    const totalFundValueAfter = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());
    checkAlmostSame(totalFundValueBefore, totalFundValueAfter);
  });

  it("should be able to swap tokens on balancer - batchSwap exactInput.", async () => {
    const kind = 0;
    const amount = units(1, 6);
    const pools = [
      ["0x06df3b2bbb68adc8b0e302443692037ed9f91b42000000000000000000000012", 0, 1, "500000", "0x"],
      ["0x06df3b2bbb68adc8b0e302443692037ed9f91b42000000000000000000000012", 0, 1, "500000", "0x"],
    ];
    const assetsArray = [assets.usdc, assets.usdt];
    const sender = poolLogicProxy.address;
    const recipient = poolLogicProxy.address;
    const limits = ["1000000", "-990000"];

    const IBalancerV2Vault = await hre.artifacts.readArtifact("IBalancerV2Vault");
    const iBalancerV2Vault = new ethers.utils.Interface(IBalancerV2Vault.abi);

    let swapTx = iBalancerV2Vault.encodeFunctionData("batchSwap", [
      kind,
      pools,
      assetsArray,
      [sender, false, recipient, false],
      limits,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);

    const usdtBalanceBefore = ethers.BigNumber.from(await USDT.balanceOf(poolLogicProxy.address));
    const usdcBalanceBefore = ethers.BigNumber.from(await USDC.balanceOf(poolLogicProxy.address));
    const totalFundValueBefore = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());

    await poolLogicProxy.connect(manager).execTransaction(balancer.v2Vault, swapTx);

    const usdtBalanceAfter = await USDT.balanceOf(poolLogicProxy.address);
    const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
    expect(usdcBalanceAfter).to.equal(usdcBalanceBefore.sub(amount));
    checkAlmostSame(usdtBalanceAfter, usdtBalanceBefore.add(amount));

    const totalFundValueAfter = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());
    checkAlmostSame(totalFundValueBefore, totalFundValueAfter);
  });

  it("should be able to swap tokens on balancer - batchSwap exactOutput.", async () => {
    const kind = 1;
    const amount = units(1, 6);
    const pools = [
      ["0x06df3b2bbb68adc8b0e302443692037ed9f91b42000000000000000000000012", 0, 1, "500000", "0x"],
      ["0x06df3b2bbb68adc8b0e302443692037ed9f91b42000000000000000000000012", 0, 1, "500000", "0x"],
    ];
    const assetsArray = [assets.usdc, assets.usdt];
    const sender = poolLogicProxy.address;
    const recipient = poolLogicProxy.address;
    const limits = ["1010000", "-1000000"];

    const IBalancerV2Vault = await hre.artifacts.readArtifact("IBalancerV2Vault");
    const iBalancerV2Vault = new ethers.utils.Interface(IBalancerV2Vault.abi);

    let swapTx = iBalancerV2Vault.encodeFunctionData("batchSwap", [
      kind,
      pools,
      assetsArray,
      [sender, false, recipient, false],
      limits,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);

    const usdtBalanceBefore = ethers.BigNumber.from(await USDT.balanceOf(poolLogicProxy.address));
    const usdcBalanceBefore = ethers.BigNumber.from(await USDC.balanceOf(poolLogicProxy.address));
    const totalFundValueBefore = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());

    await poolLogicProxy.connect(manager).execTransaction(balancer.v2Vault, swapTx);

    const usdtBalanceAfter = await USDT.balanceOf(poolLogicProxy.address);
    const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
    checkAlmostSame(usdcBalanceAfter, usdcBalanceBefore.sub(amount));
    expect(usdtBalanceAfter).to.equal(usdtBalanceBefore.add(amount));

    const totalFundValueAfter = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());
    checkAlmostSame(totalFundValueBefore, totalFundValueAfter);
  });

  it("should be able to join pool on balancer.", async () => {
    await poolManagerLogicProxy.connect(manager).changeAssets([[balancer_stable_pool_info.pool, false]], []);

    const poolId = "0x06df3b2bbb68adc8b0e302443692037ed9f91b42000000000000000000000012";
    const sender = poolLogicProxy.address;
    const recipient = poolLogicProxy.address;
    const assetsArray = [assets.usdc, assets.dai, assets.miMatic, assets.usdt];
    const amount = units(1, 6);
    const maxAmountsIn = [amount, 0, 0, amount];

    const IBalancerV2Vault = await hre.artifacts.readArtifact("IBalancerV2Vault");
    const iBalancerV2Vault = new ethers.utils.Interface(IBalancerV2Vault.abi);

    let joinTx = iBalancerV2Vault.encodeFunctionData("joinPool", [
      poolId,
      sender,
      recipient,
      [
        assetsArray,
        [amount, 0, amount, amount],
        ethers.utils.defaultAbiCoder.encode(["uint256", "uint256[]", "uint256"], [1, [amount, 0, amount, amount], 1]),
        false,
      ],
    ]);

    await expect(poolLogicProxy.connect(manager).execTransaction(balancer.v2Vault, joinTx)).to.be.revertedWith(
      "unsupported asset",
    );

    joinTx = iBalancerV2Vault.encodeFunctionData("joinPool", [
      poolId,
      assets.dai,
      recipient,
      [
        assetsArray,
        maxAmountsIn,
        ethers.utils.defaultAbiCoder.encode(["uint256", "uint256[]", "uint256"], [1, maxAmountsIn, 1]),
        false,
      ],
    ]);

    await expect(poolLogicProxy.connect(manager).execTransaction(balancer.v2Vault, joinTx)).to.be.revertedWith(
      "sender is not pool",
    );

    joinTx = iBalancerV2Vault.encodeFunctionData("joinPool", [
      poolId,
      sender,
      assets.dai,
      [
        assetsArray,
        maxAmountsIn,
        ethers.utils.defaultAbiCoder.encode(["uint256", "uint256[]", "uint256"], [1, maxAmountsIn, 1]),
        false,
      ],
    ]);

    await expect(poolLogicProxy.connect(manager).execTransaction(balancer.v2Vault, joinTx)).to.be.revertedWith(
      "recipient is not pool",
    );

    joinTx = iBalancerV2Vault.encodeFunctionData("joinPool", [
      poolId,
      sender,
      recipient,
      [
        assetsArray,
        maxAmountsIn,
        ethers.utils.defaultAbiCoder.encode(["uint256", "uint256[]", "uint256"], [1, maxAmountsIn, 1]),
        false,
      ],
    ]);

    const IERC20 = await hre.artifacts.readArtifact("IERC20");
    const iERC20 = new ethers.utils.Interface(IERC20.abi);
    let approveABI = iERC20.encodeFunctionData("approve", [balancer.v2Vault, amount]);
    await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);
    await poolLogicProxy.connect(manager).execTransaction(assets.usdt, approveABI);

    const usdtBalanceBefore = ethers.BigNumber.from(await USDT.balanceOf(poolLogicProxy.address));
    const usdcBalanceBefore = ethers.BigNumber.from(await USDC.balanceOf(poolLogicProxy.address));
    const totalFundValueBefore = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());

    await poolLogicProxy.connect(manager).execTransaction(balancer.v2Vault, joinTx);

    const usdtBalanceAfter = await USDT.balanceOf(poolLogicProxy.address);
    const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
    expect(usdcBalanceAfter).to.equal(usdcBalanceBefore.sub(amount));
    expect(usdtBalanceAfter).to.equal(usdtBalanceBefore.sub(amount));

    const totalFundValueAfter = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());
    checkAlmostSame(totalFundValueBefore, totalFundValueAfter);
  });

  it("should be able to exit pool on balancer.", async () => {
    const poolId = "0x06df3b2bbb68adc8b0e302443692037ed9f91b42000000000000000000000012";
    const sender = poolLogicProxy.address;
    const recipient = poolLogicProxy.address;
    const assetsArray = [assets.usdc, assets.dai, assets.miMatic, assets.usdt];
    const amount = units(1, 6);
    const minAmountsOut = [0, 0, 0, 0];

    const IBalancerV2Vault = await hre.artifacts.readArtifact("IBalancerV2Vault");
    const iBalancerV2Vault = new ethers.utils.Interface(IBalancerV2Vault.abi);

    let exitTx = iBalancerV2Vault.encodeFunctionData("exitPool", [
      poolId,
      sender,
      recipient,
      [
        assetsArray,
        minAmountsOut,
        ethers.utils.defaultAbiCoder.encode(
          ["uint256", "uint256", "uint256"],
          [0, await BALANCERLP_STABLE.balanceOf(poolLogicProxy.address), 2],
        ),
        false,
      ],
    ]);

    await expect(poolLogicProxy.connect(manager).execTransaction(balancer.v2Vault, exitTx)).to.be.revertedWith(
      "unsupported asset",
    );

    exitTx = iBalancerV2Vault.encodeFunctionData("exitPool", [
      poolId,
      assets.dai,
      recipient,
      [
        assetsArray,
        minAmountsOut,
        ethers.utils.defaultAbiCoder.encode(
          ["uint256", "uint256", "uint256"],
          [0, await BALANCERLP_STABLE.balanceOf(poolLogicProxy.address), 0],
        ),
        false,
      ],
    ]);

    await expect(poolLogicProxy.connect(manager).execTransaction(balancer.v2Vault, exitTx)).to.be.revertedWith(
      "sender is not pool",
    );

    exitTx = iBalancerV2Vault.encodeFunctionData("exitPool", [
      poolId,
      sender,
      assets.dai,
      [
        assetsArray,
        minAmountsOut,
        ethers.utils.defaultAbiCoder.encode(
          ["uint256", "uint256", "uint256"],
          [0, await BALANCERLP_STABLE.balanceOf(poolLogicProxy.address), 0],
        ),
        false,
      ],
    ]);

    await expect(poolLogicProxy.connect(manager).execTransaction(balancer.v2Vault, exitTx)).to.be.revertedWith(
      "recipient is not pool",
    );

    exitTx = iBalancerV2Vault.encodeFunctionData("exitPool", [
      poolId,
      sender,
      recipient,
      [
        assetsArray,
        minAmountsOut,
        ethers.utils.defaultAbiCoder.encode(
          ["uint256", "uint256", "uint256"],
          [0, await BALANCERLP_STABLE.balanceOf(poolLogicProxy.address), 0],
        ),
        false,
      ],
    ]);

    const usdcBalanceBefore = ethers.BigNumber.from(await USDC.balanceOf(poolLogicProxy.address));
    const usdtBalanceBefore = ethers.BigNumber.from(await USDT.balanceOf(poolLogicProxy.address));
    const totalFundValueBefore = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());

    await poolLogicProxy.connect(manager).execTransaction(balancer.v2Vault, exitTx);

    const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
    const usdtBalanceAfter = await USDT.balanceOf(poolLogicProxy.address);
    checkAlmostSame(usdcBalanceAfter, usdcBalanceBefore.add(amount.mul(2)));
    expect(usdtBalanceAfter).to.be.equal(usdtBalanceBefore);

    const totalFundValueAfter = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());
    checkAlmostSame(totalFundValueBefore, totalFundValueAfter);
  });

  it("should be able to join weth-bal pool on balancer.", async () => {
    // Deposit 0.1 WETH
    await poolManagerLogicProxy.connect(manager).changeAssets([[assets.weth, true]], []);
    await WETH.approve(poolLogicProxy.address, units(1).div(10));
    await poolLogicProxy.deposit(assets.weth, units(1).div(10));

    await poolManagerLogicProxy.connect(manager).changeAssets([[balancer80_weth20_pool_info.pool, false]], []);

    const poolId = balancer80_weth20_pool_info.poolId;
    const sender = poolLogicProxy.address;
    const recipient = poolLogicProxy.address;
    const assetsArray = balancer80_weth20_pool_info.tokens;
    const amount = units(1).div(10);
    const maxAmountsIn = [amount, 0];

    const IBalancerV2Vault = await hre.artifacts.readArtifact("IBalancerV2Vault");
    const iBalancerV2Vault = new ethers.utils.Interface(IBalancerV2Vault.abi);

    const joinTx = iBalancerV2Vault.encodeFunctionData("joinPool", [
      poolId,
      sender,
      recipient,
      [
        assetsArray,
        maxAmountsIn,
        ethers.utils.defaultAbiCoder.encode(["uint256", "uint256", "uint256"], [2, units(1), 0]),
        false,
      ],
    ]);

    const IERC20 = await hre.artifacts.readArtifact("IERC20");
    const iERC20 = new ethers.utils.Interface(IERC20.abi);
    let approveABI = iERC20.encodeFunctionData("approve", [balancer.v2Vault, amount]);
    await poolLogicProxy.connect(manager).execTransaction(assets.weth, approveABI);

    const lpBalanceBefore = ethers.BigNumber.from(await BALANCERLP_WETH_BALANCER.balanceOf(poolLogicProxy.address));
    const wethBalanceBefore = ethers.BigNumber.from(await WETH.balanceOf(poolLogicProxy.address));
    const totalFundValueBefore = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());

    await poolLogicProxy.connect(manager).execTransaction(balancer.v2Vault, joinTx);

    const lpBalanceAfter = ethers.BigNumber.from(await BALANCERLP_WETH_BALANCER.balanceOf(poolLogicProxy.address));
    expect(lpBalanceAfter).to.gt(lpBalanceBefore);

    const wethBalanceAfter = await WETH.balanceOf(poolLogicProxy.address);
    expect(wethBalanceAfter).to.lt(wethBalanceBefore);

    const totalFundValueAfter = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());
    checkAlmostSame(totalFundValueBefore, totalFundValueAfter);
  });

  it("should be able to exit weth-bal pool on balancer.", async () => {
    const poolId = balancer80_weth20_pool_info.poolId;
    const sender = poolLogicProxy.address;
    const recipient = poolLogicProxy.address;
    const assetsArray = balancer80_weth20_pool_info.tokens;
    const minAmountsOut = [0, 0];

    const IBalancerV2Vault = await hre.artifacts.readArtifact("IBalancerV2Vault");
    const iBalancerV2Vault = new ethers.utils.Interface(IBalancerV2Vault.abi);

    const exitTx = iBalancerV2Vault.encodeFunctionData("exitPool", [
      poolId,
      sender,
      recipient,
      [
        assetsArray,
        minAmountsOut,
        ethers.utils.defaultAbiCoder.encode(
          ["uint256", "uint256"],
          [1, await BALANCERLP_WETH_BALANCER.balanceOf(poolLogicProxy.address)],
        ),
        false,
      ],
    ]);

    const lpBalanceBefore = ethers.BigNumber.from(await BALANCERLP_WETH_BALANCER.balanceOf(poolLogicProxy.address));
    const wethBalanceBefore = ethers.BigNumber.from(await WETH.balanceOf(poolLogicProxy.address));
    const balancerBalanceBefore = ethers.BigNumber.from(await BALANCER.balanceOf(poolLogicProxy.address));
    const totalFundValueBefore = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());

    await expect(poolLogicProxy.connect(manager).execTransaction(balancer.v2Vault, exitTx)).to.be.revertedWith(
      "unsupported asset",
    );

    await poolManagerLogicProxy.connect(manager).changeAssets([[assets.balancer, true]], []);
    await poolLogicProxy.connect(manager).execTransaction(balancer.v2Vault, exitTx);

    const lpBalanceAfter = ethers.BigNumber.from(await BALANCERLP_WETH_BALANCER.balanceOf(poolLogicProxy.address));
    expect(lpBalanceAfter).to.lt(lpBalanceBefore);

    const wethBalanceAfter = ethers.BigNumber.from(await WETH.balanceOf(poolLogicProxy.address));
    const balancerBalanceAfter = ethers.BigNumber.from(await BALANCER.balanceOf(poolLogicProxy.address));
    expect(wethBalanceAfter).to.gt(wethBalanceBefore);
    expect(balancerBalanceAfter).to.gt(balancerBalanceBefore);

    const totalFundValueAfter = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());
    checkAlmostSame(totalFundValueBefore, totalFundValueAfter);
  });
});
