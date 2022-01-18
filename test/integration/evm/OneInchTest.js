const { ethers, upgrades } = require("hardhat");
const { expect, use } = require("chai");
const chaiAlmost = require("chai-almost");
const axios = require("axios");
const { checkAlmostSame, getAmountOut, units } = require("../../TestHelpers");
const {
  ZERO_ADDRESS,
  sushi,
  uniswapV2,
  oneinch,
  assets,
  price_feeds,
} = require("../../../config/chainData/ethereum-data");

use(chaiAlmost());

describe("OneInch V4 Test", function () {
  let WETH, USDC, USDT, UniswapRouter;
  let logicOwner, manager, dao, user;
  let PoolFactory, PoolLogic, PoolManagerLogic, assetHandler;
  let poolFactory, poolLogic, poolManagerLogic, poolLogicProxy, poolManagerLogicProxy, fundAddress;
  let uniswapV2RouterGuard;

  before(async function () {
    [logicOwner, manager, dao, user] = await ethers.getSigners();

    const AssetHandlerLogic = await ethers.getContractFactory("AssetHandler");

    const Governance = await ethers.getContractFactory("Governance");
    let governance = await Governance.deploy();
    console.log("governance deployed to:", governance.address);

    const PoolPerformance = await ethers.getContractFactory("PoolPerformance");
    const poolPerformance = await upgrades.deployProxy(PoolPerformance);
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

    const ERC20Guard = await ethers.getContractFactory("ERC20Guard");
    erc20Guard = await ERC20Guard.deploy();
    erc20Guard.deployed();

    const UniswapV2RouterGuard = await ethers.getContractFactory("UniswapV2RouterGuard");
    uniswapV2RouterGuard = await UniswapV2RouterGuard.deploy(2, 100); // set slippage 2% for testing
    uniswapV2RouterGuard.deployed();

    const OneInchV4Guard = await ethers.getContractFactory("OneInchV4Guard");
    oneInchV4Guard = await OneInchV4Guard.deploy(2, 100); // set slippage 2%
    oneInchV4Guard.deployed();

    await governance.setAssetGuard(0, erc20Guard.address);
    await governance.setAssetGuard(2, erc20Guard.address); // as normal erc20 token
    await governance.setContractGuard(uniswapV2.router, uniswapV2RouterGuard.address);
    await governance.setContractGuard(sushi.router, uniswapV2RouterGuard.address);
    await governance.setContractGuard(oneinch.v4Router, oneInchV4Guard.address);

    await poolFactory.setExitFee(5, 1000); // 0.5%
  });

  it("Should be able to get USDC", async function () {
    const IWETH = await hre.artifacts.readArtifact("IWETH");
    WETH = await ethers.getContractAt(IWETH.abi, assets.weth);
    const IERC20 = await hre.artifacts.readArtifact("IERC20");
    USDT = await ethers.getContractAt(IERC20.abi, assets.usdt);
    USDC = await ethers.getContractAt(IERC20.abi, assets.usdc);
    const IUniswapV2Router = await hre.artifacts.readArtifact("IUniswapV2Router");
    UniswapRouter = await ethers.getContractAt(IUniswapV2Router.abi, uniswapV2.router);

    const amount = units(100, 18);
    // deposit ETH -> WETH
    await WETH.deposit({ value: amount });
    // WETH -> USDT
    await WETH.approve(uniswapV2.router, amount);
    await UniswapRouter.swapExactTokensForTokens(
      amount,
      0,
      [assets.weth, assets.usdc],
      logicOwner.address,
      Math.floor(Date.now() / 1000 + 100000000),
    );
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
    expect(numberOfSupportedAssets).to.eq(2);
    expect(await poolManagerLogicProxy.isSupportedAsset(assets.usdc)).to.be.true;
    expect(await poolManagerLogicProxy.isSupportedAsset(assets.weth)).to.be.true;

    //Other assets are not supported
    expect(await poolManagerLogicProxy.isSupportedAsset(assets.usdt)).to.be.false;
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

    let totalFundValue = await poolManagerLogicProxy.totalFundValue();
    expect(totalFundValue.toString()).to.equal("0");

    const amount = units(200000, 6);
    await expect(poolLogicProxy.deposit(assets.usdt, amount)).to.be.revertedWith("invalid deposit asset");

    await USDC.approve(poolLogicProxy.address, amount);
    await poolLogicProxy.deposit(assets.usdc, amount);
    let event = await depositEvent;

    expect(event.fundAddress).to.equal(poolLogicProxy.address);
    expect(event.investor).to.equal(logicOwner.address);
    checkAlmostSame(event.valueDeposited, units(200000, 18));
    checkAlmostSame(event.fundTokensReceived, units(200000, 18));
    checkAlmostSame(event.totalInvestorFundTokens, units(200000, 18));
    checkAlmostSame(event.fundValue, units(200000, 18));
    checkAlmostSame(event.totalSupply, units(200000, 18));
  });

  it("Should be able to approve", async () => {
    const IERC20 = await hre.artifacts.readArtifact("IERC20");
    const iERC20 = new ethers.utils.Interface(IERC20.abi);
    const amount = units(200000, 6);
    let approveABI = iERC20.encodeFunctionData("approve", [assets.usdc, amount]);
    await expect(poolLogicProxy.connect(manager).execTransaction(assets.usdt, approveABI)).to.be.revertedWith(
      "asset not enabled in pool",
    );

    await expect(poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI)).to.be.revertedWith(
      "unsupported spender approval",
    );

    approveABI = iERC20.encodeFunctionData("approve", [oneinch.v4Router, amount]);
    await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);
  });

  it("should be able to swap tokens on oneInch - unoswap.", async () => {
    const srcAsset = assets.usdc;
    const dstAsset = assets.usdt;
    const srcAmount = units(1000, 6);
    const fromAddress = poolLogicProxy.address;
    const toAddress = poolLogicProxy.address;
    const referrerAddress = "";

    const IAggregationRouterV3 = await hre.artifacts.readArtifact("IAggregationRouterV3");
    const iAggregationRouterV3 = new ethers.utils.Interface(IAggregationRouterV3.abi);

    let swapTx = iAggregationRouterV3.encodeFunctionData("unoswap", [
      srcAsset,
      srcAmount,
      ethers.BigNumber.from(await getAmountOut(sushi.router, srcAmount, [assets.usdc, assets.usdt]))
        .mul(95)
        .div(100),
      ["0x80000000000000003b6d0340" + sushi.pools.dai_usdt.address.slice(2, sushi.pools.dai_usdt.address.length)],
    ]);

    await expect(poolLogicProxy.connect(manager).execTransaction(oneinch.v4Router, swapTx)).to.be.revertedWith(
      "invalid path",
    );

    swapTx = await getOneInchSwapTransaction({
      srcAsset,
      dstAsset,
      srcAmount,
      fromAddress,
      toAddress,
      referrerAddress,
    });

    await expect(poolLogicProxy.connect(manager).execTransaction(oneinch.v4Router, swapTx)).to.be.revertedWith(
      "unsupported destination asset",
    );

    await poolManagerLogicProxy.connect(manager).changeAssets([[assets.usdt, false]], []);

    await oneInchV4Guard.setSlippageLimit(1, 1000); // 0.1%

    await expect(poolLogicProxy.connect(manager).execTransaction(oneinch.v4Router, swapTx)).to.be.revertedWith(
      "slippage limit exceed",
    );

    await oneInchV4Guard.setSlippageLimit(10, 100); // 10%

    const usdtBalanceBefore = ethers.BigNumber.from(await USDT.balanceOf(poolLogicProxy.address));
    const usdcBalanceBefore = ethers.BigNumber.from(await USDC.balanceOf(poolLogicProxy.address));

    await poolLogicProxy.connect(manager).execTransaction(oneinch.v4Router, swapTx);

    const usdtBalanceAfter = await USDT.balanceOf(poolLogicProxy.address);
    const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
    checkAlmostSame(usdcBalanceAfter, usdcBalanceBefore.sub(srcAmount));
    checkAlmostSame(usdtBalanceAfter, usdtBalanceBefore.add(srcAmount));
  });

  // getOneInchSwapTransaction is returning a `uniswapV3Swap()` not `swap()` which is a function we don't IHasSupportedAsset
  // this needs to be investigated
  it("should be able to swap tokens on oneInch - swap.", async () => {
    const srcAsset = assets.usdc;
    const dstAsset = assets.usdt;
    const srcAmount = units(199000, 6);
    const fromAddress = poolLogicProxy.address;
    const toAddress = poolLogicProxy.address;
    const referrerAddress = "";

    /**
     * Example Swap Transaction USDT -> USDC
     * 0x7c02520000000000000000000000000027239549dd40e1d60f5b80b0c4196923745b1fd200000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000180000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec7000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb4800000000000000000000000027239549dd40e1d60f5b80b0c4196923745b1fd20000000000000000000000004f6d9fd7e4ce9a64b1d3e62c6fa9cf186b5e8c3d00000000000000000000000000000000000000000000000000000002540be400000000000000000000000000000000000000000000000000000000024e07705c00000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002a0000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000016080000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000064eb5625d9000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec700000000000000000000000040bbde0ec6f177c4a67360d0f0969cfc464b0bb400000000000000000000000000000000000000000000000000000002540be4000000000000000000000000000000000000000000000000000000000080000000000000000000000040bbde0ec6f177c4a67360d0f0969cfc464b0bb40000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000044404a1f8a00000000000000000000000000000000000000000000000000000002540be4000000000000000000000000004f6d9fd7e4ce9a64b1d3e62c6fa9cf186b5e8c3d00000000000000000000000000000000000000000000000000000000
     * Example Swap Transaction USDC -> USDT
     * 0x7c02520000000000000000000000000027239549dd40e1d60f5b80b0c4196923745b1fd200000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000180000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec700000000000000000000000027239549dd40e1d60f5b80b0c4196923745b1fd20000000000000000000000004f6d9fd7e4ce9a64b1d3e62c6fa9cf186b5e8c3d000000000000000000000000000000000000000000000000000000046c7cfe000000000000000000000000000000000000000000000000000000000460e6d94800000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002a0000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000016080000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000064eb5625d9000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb4800000000000000000000000040bbde0ec6f177c4a67360d0f0969cfc464b0bb4000000000000000000000000000000000000000000000000000000046c7cfe000000000000000000000000000000000000000000000000000000000080000000000000000000000040bbde0ec6f177c4a67360d0f0969cfc464b0bb400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000448999541a000000000000000000000000000000000000000000000000000000046c7cfe000000000000000000000000004f6d9fd7e4ce9a64b1d3e62c6fa9cf186b5e8c3d00000000000000000000000000000000000000000000000000000000
     */
    let swapTx = await getOneInchSwapTransaction({
      srcAsset,
      dstAsset: assets.dai,
      srcAmount,
      fromAddress,
      toAddress,
      referrerAddress,
    });

    await expect(poolLogicProxy.connect(manager).execTransaction(oneinch.v4Router, swapTx)).to.be.revertedWith(
      "unsupported destination asset",
    );

    swapTx = await getOneInchSwapTransaction({
      srcAsset,
      dstAsset,
      srcAmount,
      fromAddress,
      toAddress: ZERO_ADDRESS,
      referrerAddress,
    });

    await expect(poolLogicProxy.connect(manager).execTransaction(oneinch.v4Router, swapTx)).to.be.revertedWith(
      "recipient is not pool",
    );

    swapTx = await getOneInchSwapTransaction({
      srcAsset,
      dstAsset,
      srcAmount,
      fromAddress,
      toAddress,
      referrerAddress,
    });

    const usdtBalanceBefore = ethers.BigNumber.from(await USDT.balanceOf(poolLogicProxy.address));
    const usdcBalanceBefore = ethers.BigNumber.from(await USDC.balanceOf(poolLogicProxy.address));

    await poolLogicProxy.connect(manager).execTransaction(oneinch.v4Router, swapTx);

    const usdtBalanceAfter = await USDT.balanceOf(poolLogicProxy.address);
    const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
    checkAlmostSame(usdcBalanceAfter, usdcBalanceBefore.sub(srcAmount));
    checkAlmostSame(usdtBalanceAfter, usdtBalanceBefore.add(srcAmount));
  });
});

const getOneInchSwapTransaction = async (params, retry = 3) => {
  const { srcAsset, dstAsset, srcAmount, fromAddress, toAddress, referrerAddress } = params;
  const apiUrl = `https://api.1inch.exchange/v4.0/1/swap?fromTokenAddress=${srcAsset}&toTokenAddress=${dstAsset}&amount=${srcAmount.toString()}&fromAddress=${fromAddress}&destReceiver=${toAddress}&referrerAddress=${referrerAddress}&slippage=1&disableEstimate=true`;
  try {
    const response = await axios.get(apiUrl);
    const calldata = response.data.tx.data;
    return calldata;
  } catch (e) {
    if (retry >= 1) {
      return getOneInchSwapTransaction(params, retry - 1);
    }
    throw error("failed to call oneInch api");
  }
};
