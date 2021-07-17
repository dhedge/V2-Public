const { ethers, upgrades } = require("hardhat");
const { expect, use } = require("chai");
const chaiAlmost = require("chai-almost");
const { checkAlmostSame } = require("../../TestHelpers");

use(chaiAlmost());

const uniswapV3Factory = "0x1F98431c8aD98523631AE4a59f267346ea31F984";
const uniswapV3Router = "0xE592427A0AEce92De3Edee1F18E0157C05861564";

// For mainnet
const weth = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
const usdc = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
const usdt = "0xdAC17F958D2ee523a2206206994597C13D831ec7";
const sushi_usdc_usdt = "0xD86A120a06255Df8D4e2248aB04d4267E23aDfaA";
const eth_price_feed = "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419";
const usdt_price_feed = "0x3E7d1eAB13ad0104d2750B8863b489D65364e32D";
const usdc_price_feed = "0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6";
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
const deadLine = Math.floor(Date.now() / 1000 + 100000000);

describe("Uniswap V3 Test", function () {
  let WETH, USDC, USDT, SushiUsdcUsdt, UniswapRouter;
  let logicOwner, manager, dao, user;
  let PoolFactory, PoolLogic, PoolManagerLogic, assetHandler;
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
    erc20Guard.deployed();

    const UniswapV3SwapGuard = await ethers.getContractFactory("UniswapV3SwapGuard");
    uniswapV3SwapGuard = await UniswapV3SwapGuard.deploy();
    uniswapV3SwapGuard.deployed();

    await governance.setAssetGuard(0, erc20Guard.address);
    await governance.setContractGuard(uniswapV3Router, uniswapV3SwapGuard.address);
  });

  it("Should be able to get WETH", async function () {
    const IWETH = await hre.artifacts.readArtifact("IWETH");
    WETH = await ethers.getContractAt(IWETH.abi, weth);
    const IERC20 = await hre.artifacts.readArtifact("IERC20");
    USDT = await ethers.getContractAt(IERC20.abi, usdt);
    USDC = await ethers.getContractAt(IERC20.abi, usdc);
    SushiUsdcUsdt = await ethers.getContractAt(IERC20.abi, sushi_usdc_usdt);
    const IUniswapV3Router = await hre.artifacts.readArtifact("IUniswapV3Router");
    UniswapRouter = await ethers.getContractAt(IUniswapV3Router.abi, uniswapV3Router);
    // deposit ETH -> WETH
    await WETH.deposit({ value: (10e18).toString() });
    // WETH -> USDT
    let sourceAmount = (5e18).toString();
    await WETH.approve(uniswapV3Router, (5e18).toString());
    const exactInputSingleParams = {
      tokenIn: weth,
      tokenOut: usdc,
      fee: 10000,
      recipient: logicOwner.address,
      deadline: deadLine,
      amountIn: sourceAmount,
      amountOutMinimum: 0,
      sqrtPriceLimitX96: 0,
    };
    await UniswapRouter.exactInputSingle(exactInputSingleParams);

    // const path =
    //   "0x" +
    //   weth.substring(2) + // source asset
    //   "0001f4" + // fee
    //   usdc.substring(2) + // path asset
    //   "0001f4" + // fee
    //   usdt.substring(2); // destination asset
    // const exactInputParams = {
    //   path: path,
    //   recipient: logicOwner.address,
    //   deadline: deadLine,
    //   amountIn: sourceAmount,
    //   amountOutMinimum: 0,
    // };
    // await UniswapRouter.exactInput(exactInputParams);
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

    let totalFundValue = await poolManagerLogicProxy.totalFundValue();
    expect(totalFundValue.toString()).to.equal("0");

    await expect(poolLogicProxy.deposit(usdt, (100e6).toString())).to.be.revertedWith("invalid deposit asset");

    // Approve and deposit 100 USDC
    await USDC.approve(poolLogicProxy.address, (100e6).toString());
    await poolLogicProxy.deposit(usdc, (100e6).toString());
    let event = await depositEvent;

    expect(event.fundAddress).to.equal(poolLogicProxy.address);
    expect(event.investor).to.equal(logicOwner.address);
    checkAlmostSame(event.valueDeposited, (100e18).toString());
    checkAlmostSame(event.fundTokensReceived, (100e18).toString());
    checkAlmostSame(event.totalInvestorFundTokens, (100e18).toString());
    checkAlmostSame(event.fundValue, (100e18).toString());
    checkAlmostSame(event.totalSupply, (100e18).toString());

    // Approve and deposit 5 WETH
    await WETH.approve(poolLogicProxy.address, (5e18).toString());
    await poolLogicProxy.deposit(weth, (5e18).toString());
  });

  it("Should be able to approve", async () => {
    const IERC20 = await hre.artifacts.readArtifact("IERC20");
    const iERC20 = new ethers.utils.Interface(IERC20.abi);
    let approveABI = iERC20.encodeFunctionData("approve", [usdc, (100e6).toString()]);
    await expect(poolLogicProxy.connect(manager).execTransaction(usdt, approveABI)).to.be.revertedWith(
      "asset not enabled in pool",
    );

    await expect(poolLogicProxy.connect(manager).execTransaction(usdc, approveABI)).to.be.revertedWith(
      "unsupported spender approval",
    );

    // Approve to swap 100 USDC
    approveABI = iERC20.encodeFunctionData("approve", [uniswapV3Router, (100e6).toString()]);
    await poolLogicProxy.connect(manager).execTransaction(usdc, approveABI);

    // Approve to swap 1 WETH
    approveABI = iERC20.encodeFunctionData("approve", [uniswapV3Router, (1e18).toString()]);
    await poolLogicProxy.connect(manager).execTransaction(weth, approveABI);
  });

  it("should be able to swap tokens - direct swap", async () => {
    let exchangeEvent = new Promise((resolve, reject) => {
      uniswapV3SwapGuard.on("Exchange", (pool, sourceAsset, sourceAmount, destinationAsset, time, event) => {
        event.removeListener();

        resolve({
          pool: pool,
          sourceAsset: sourceAsset,
          sourceAmount: sourceAmount,
          destinationAsset: destinationAsset,
          time: time,
        });
      });

      setTimeout(() => {
        reject(new Error("timeout"));
      }, 60000);
    });

    const sourceAmount = (5e6).toString();
    const IUniswapV3Router = await hre.artifacts.readArtifact("IUniswapV3Router");
    const iUniswapV3Router = new ethers.utils.Interface(IUniswapV3Router.abi);
    const exactInputSingleParams = {
      tokenIn: usdc,
      tokenOut: weth,
      fee: 10000,
      recipient: poolLogicProxy.address,
      deadline: deadLine,
      amountIn: sourceAmount,
      amountOutMinimum: 0,
      sqrtPriceLimitX96: 0,
    };
    let badExactInputSingleParams = exactInputSingleParams;

    // fail to swap direct asset to asset because it is interaction is with 0x0 address
    let swapABI = iUniswapV3Router.encodeFunctionData("exactInputSingle", [exactInputSingleParams]);
    await expect(
      poolLogicProxy.connect(manager).execTransaction("0x0000000000000000000000000000000000000000", swapABI),
    ).to.be.revertedWith("non-zero address is required");

    // fail to swap direct asset to asset because unsupported source asset
    badExactInputSingleParams.tokenIn = usdt;
    swapABI = iUniswapV3Router.encodeFunctionData("exactInputSingle", [badExactInputSingleParams]);
    await expect(poolLogicProxy.connect(manager).execTransaction(uniswapV3Router, swapABI)).to.be.revertedWith(
      "unsupported source asset",
    );
    badExactInputSingleParams.tokenIn = usdc;

    // fail to swap direct asset to asset because unsupported destination asset
    badExactInputSingleParams.tokenOut = usdt;
    swapABI = iUniswapV3Router.encodeFunctionData("exactInputSingle", [badExactInputSingleParams]);
    await expect(poolLogicProxy.connect(manager).execTransaction(uniswapV3Router, swapABI)).to.be.revertedWith(
      "unsupported destination asset",
    );
    badExactInputSingleParams.tokenOut = weth;

    // fail to swap direct asset to asset because recipient is not the pool address
    badExactInputSingleParams.recipient = user.address;
    swapABI = iUniswapV3Router.encodeFunctionData("exactInputSingle", [badExactInputSingleParams]);
    await expect(poolLogicProxy.connect(manager).execTransaction(uniswapV3Router, swapABI)).to.be.revertedWith(
      "recipient is not pool",
    );
    exactInputSingleParams.recipient = poolLogicProxy.address;

    // succeed swapping direct asset to asset
    swapABI = iUniswapV3Router.encodeFunctionData("exactInputSingle", [exactInputSingleParams]);
    await poolLogicProxy.connect(manager).execTransaction(uniswapV3Router, swapABI);

    let event = await exchangeEvent;
    expect(event.sourceAsset).to.equal(usdc);
    expect(event.sourceAmount).to.equal(sourceAmount);
    expect(event.destinationAsset).to.equal(weth);
  });

  it("should be able to swap tokens - multi swap", async () => {
    let exchangeEvent = new Promise((resolve, reject) => {
      uniswapV3SwapGuard.on("Exchange", (pool, sourceAsset, sourceAmount, destinationAsset, time, event) => {
        event.removeListener();

        resolve({
          pool: pool,
          sourceAsset: sourceAsset,
          sourceAmount: sourceAmount,
          destinationAsset: destinationAsset,
          time: time,
        });
      });

      setTimeout(() => {
        reject(new Error("timeout"));
      }, 60000);
    });

    await poolManagerLogicProxy.connect(manager).changeAssets([[usdt, false]], []);

    const sourceAmount = (1e18).toString();
    const IUniswapV3Router = await hre.artifacts.readArtifact("IUniswapV3Router");
    const iUniswapV3Router = new ethers.utils.Interface(IUniswapV3Router.abi);
    // https://etherscan.io/tx/0xf74db2cc2a321de029800754ed3c8c7b85a9e1233e3bd2001218d0f407fd3a93
    // data on etherscan: 0xc04b8d59000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000060f1c58700000000000000000000000000000000000000000000000000000001126dc7d6000000000000000000000000000000000000000000000000210a5097b6c2a7010000000000000000000000000000000000000000000000000000000000000042
    // dac17f958d2ee523a2206206994597c13d831ec7 0001f4 a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48 0001f4 c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000000000000000000000

    // data we have:      0xc04b8d59000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000893bacb707c0c0d9a46a3eaea2c3b44df449137b0000000000000000000000000000000000000000000000000000000066e7a8180000000000000000000000000000000000000000000000008ac7230489e8000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000042
    // a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48 000bb8 c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2 000bb8 dac17f958d2ee523a2206206994597c13d831ec7000000000000000000000000000000000000000000000000000000000000

    // path on etherscan: 0x dac17f958d2ee523a2206206994597c13d831ec7 0001f4 a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48 0001f4 c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2
    // path we have:      0x C02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2 0001f4 A0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 0001f4 dAC17F958D2ee523a2206206994597C13D831ec7
    const path =
      "0x" +
      weth.substring(2) + // source asset
      "0001f4" + // fee
      usdc.substring(2) + // path asset
      "0001f4" + // fee
      usdt.substring(2); // destination asset
    const exactInputParams = {
      path: path,
      recipient: poolLogicProxy.address,
      deadline: deadLine,
      amountIn: sourceAmount,
      amountOutMinimum: 0,
    };
    let badExactInputParams = exactInputParams;
    let badPath = path;

    // fail to swap direct asset to asset because it is interaction is with 0x0 address
    let swapABI = iUniswapV3Router.encodeFunctionData("exactInput", [exactInputParams]);
    await expect(poolLogicProxy.connect(manager).execTransaction(ZERO_ADDRESS, swapABI)).to.be.revertedWith(
      "non-zero address is required",
    );

    // fail to swap direct asset to asset because unsupported source asset
    badExactInputParams.path =
      "0x" +
      sushi_usdc_usdt.substring(2) + // unsupported asset
      "000bb8" +
      usdc.substring(2) +
      "000bb8" +
      usdt.substring(2);
    swapABI = iUniswapV3Router.encodeFunctionData("exactInput", [badExactInputParams]);
    await expect(poolLogicProxy.connect(manager).execTransaction(uniswapV3Router, swapABI)).to.be.revertedWith(
      "unsupported source asset",
    );

    // // TODO: add invalid path asset check if enabled in the Uniswap V3 swap guard
    // // fail to swap direct asset to asset because invalid path asset, unsupported by dhedge protocol
    // badExactInputParams.path =
    //   '0x' +
    //   susd.substring(2) +
    //   '000bb8' +
    //   badtoken.substring(2) + // invalid asset
    //   '000bb8' +
    //   seth.substring(2);
    // swapABI = iUniswapV3Router.encodeFunctionData('exactInput', [badExactInputParams]);
    // await expect(poolLogicProxy.connect(manager).execTransaction(uniswapV3Router.address, swapABI)).to.be.revertedWith(
    //   'invalid path asset',
    // );

    // fail to swap direct asset to asset because unsupported destination asset
    badExactInputParams.path =
      "0x" + weth.substring(2) + "000bb8" + usdc.substring(2) + "000bb8" + sushi_usdc_usdt.substring(2); // unsupported asset
    swapABI = iUniswapV3Router.encodeFunctionData("exactInput", [badExactInputParams]);
    await expect(poolLogicProxy.connect(manager).execTransaction(uniswapV3Router, swapABI)).to.be.revertedWith(
      "unsupported destination asset",
    );
    badExactInputParams.path = path;

    // fail to swap direct asset to asset because recipient is not the pool address
    badExactInputParams.recipient = user.address;
    swapABI = iUniswapV3Router.encodeFunctionData("exactInput", [exactInputParams]);
    await expect(poolLogicProxy.connect(manager).execTransaction(uniswapV3Router, swapABI)).to.be.revertedWith(
      "recipient is not pool",
    );

    exactInputParams.recipient = poolLogicProxy.address;
    // succeed swapping direct asset to asset
    console.log("exactInputParams: ", exactInputParams);
    swapABI = iUniswapV3Router.encodeFunctionData("exactInput", [exactInputParams]);
    await poolLogicProxy.connect(manager).execTransaction(uniswapV3Router, swapABI);

    let event = await exchangeEvent;
    expect(event.sourceAsset).to.equal(weth);
    expect(event.sourceAmount).to.equal(sourceAmount);
    expect(event.destinationAsset).to.equal(usdt);
  });

});
