const { ethers, upgrades, artifacts } = require("hardhat");
const { expect, use } = require("chai");
const chaiAlmost = require("chai-almost");
const { checkAlmostSame, units, currentBlockTimestamp } = require("../../TestHelpers");
const { aave, quickswap, assets, price_feeds } = require("../polygon-data");

use(chaiAlmost());

describe("ManagerFee Test", function () {
  let WMatic, USDC;
  let logicOwner, manager, dao, user;
  let PoolFactory, PoolLogic, PoolManagerLogic;
  let poolFactory, poolLogic, poolManagerLogic, poolLogicProxy, poolManagerLogicProxy, fundAddress;
  let usdc_price_feed, latestRoundDataABI;

  before(async function () {
    [logicOwner, manager, dao, user] = await ethers.getSigners();

    const MockContract = await ethers.getContractFactory("MockContract");
    usdc_price_feed = await MockContract.deploy();

    const AggregatorV3 = await artifacts.readArtifact("AggregatorV3Interface");
    const iAggregatorV3 = new ethers.utils.Interface(AggregatorV3.abi);
    latestRoundDataABI = iAggregatorV3.encodeFunctionData("latestRoundData", []);
    await usdc_price_feed.givenCalldataReturn(
      latestRoundDataABI,
      ethers.utils.solidityPack(
        ["uint256", "int256", "uint256", "uint256", "uint256"],
        [0, 100000000, 0, await currentBlockTimestamp(), 0],
      ),
    ); // $1

    const AssetHandlerLogic = await ethers.getContractFactory("AssetHandler");

    const Governance = await ethers.getContractFactory("Governance");
    const governance = await Governance.deploy();
    console.log("governance deployed to:", governance.address);

    const PoolPerformance = await ethers.getContractFactory("PoolPerformance");
    const poolPerformance = await upgrades.deployProxy(PoolPerformance, [aave.protocolDataProvider]);
    await poolPerformance.deployed();

    PoolLogic = await ethers.getContractFactory("PoolLogic");
    poolLogic = await PoolLogic.deploy();

    PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
    poolManagerLogic = await PoolManagerLogic.deploy();

    // Initialize Asset Price Consumer
    const assetWeth = { asset: assets.weth, assetType: 0, aggregator: price_feeds.eth };
    const assetUsdt = { asset: assets.usdt, assetType: 0, aggregator: price_feeds.usdt };
    const assetUsdc = { asset: assets.usdc, assetType: 0, aggregator: usdc_price_feed.address };
    const assetHandlerInitAssets = [assetWeth, assetUsdt, assetUsdc];

    assetHandler = await upgrades.deployProxy(AssetHandlerLogic, [assetHandlerInitAssets]);
    await assetHandler.deployed();
    await assetHandler.setChainlinkTimeout((3600 * 24 * 365 * 10).toString()); // 10 year expiry

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
    await erc20Guard.deployed();

    await governance.setAssetGuard(0, erc20Guard.address);

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
    let balance = await ethers.provider.getBalance(logicOwner.address);
    console.log("Matic balance: ", balance.toString());
    balance = await WMATIC.balanceOf(logicOwner.address);
    console.log("WMatic balance: ", balance.toString());
    const IUniswapV2Router = await hre.artifacts.readArtifact("IUniswapV2Router");
    const QuickSwapRouter = await ethers.getContractAt(IUniswapV2Router.abi, quickswap.router);
    // deposit Matic -> WMatic
    await WMatic.deposit({ value: units(500) });
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

    await poolFactory.createFund(
      false,
      manager.address,
      "Barren Wuffet",
      "Test Fund",
      "DHTF",
      new ethers.BigNumber.from("5000"),
      new ethers.BigNumber.from("2"), // 0% streaming fee
      [
        [assets.usdc, true],
        [assets.usdt, true],
      ],
    );

    const deployedFunds = await poolFactory.getDeployedFunds();
    const deployedFundsLength = deployedFunds.length;
    expect(deployedFundsLength.toString()).to.equal("1");

    fundAddress = deployedFunds[0];

    poolLogicProxy = await PoolLogic.attach(fundAddress);
    poolManagerLogicProxy = await PoolManagerLogic.attach(await poolLogicProxy.poolManagerLogic());
  });

  it("should be able to deposit", async function () {
    const supportedAssets = await poolManagerLogicProxy.getSupportedAssets();
    console.log("supportedAssets: ", supportedAssets);

    const chainlinkEth = await ethers.getContractAt("AggregatorV3Interface", price_feeds.eth);
    const ethPrice = await chainlinkEth.latestRoundData();
    console.log("eth price: ", ethPrice[1].toString());
    console.log("updatedAt: ", ethPrice[3].toString());

    const chainlinkUsdc = await ethers.getContractAt("AggregatorV3Interface", price_feeds.usdc);
    const usdcPrice = await chainlinkUsdc.latestRoundData();
    console.log("usdc price: ", usdcPrice[1].toString());
    console.log("updatedAt: ", usdcPrice[3].toString());

    const assetBalance = await poolManagerLogicProxy.assetBalance(assets.usdc);
    console.log("assetBalance: ", assetBalance.toString());

    const assetValue = await poolManagerLogicProxy["assetValue(address)"](assets.usdc);
    console.log("assetValue: ", assetValue.toString());

    let totalFundValue = await poolManagerLogicProxy.totalFundValue();
    expect(totalFundValue.toString()).to.equal("0");

    await expect(poolLogicProxy.deposit(assets.wmatic, (200e6).toString())).to.be.revertedWith("invalid deposit asset");

    await USDC.approve(poolLogicProxy.address, (200e6).toString());
    await poolLogicProxy.deposit(assets.usdc, (200e6).toString());

    totalFundValue = await poolManagerLogicProxy.totalFundValue();
    checkAlmostSame(totalFundValue, units(200));
  });

  it("should mint manager fee after 1 day", async () => {
    const daoFees = await poolFactory.getDaoFee();

    await usdc_price_feed.givenCalldataReturn(
      latestRoundDataABI,
      ethers.utils.solidityPack(
        ["uint256", "int256", "uint256", "uint256", "uint256"],
        [0, 110000000, 0, await currentBlockTimestamp(), 0],
      ),
    ); // $1.1

    await ethers.provider.send("evm_increaseTime", [3600 * 24]);
    await ethers.provider.send("evm_mine", []);

    const daoBalanceBefore = await poolLogicProxy.balanceOf(dao.address);
    const tokenPriceAtLastFeeMint = await poolLogicProxy.tokenPriceAtLastFeeMint();
    const availableFeePreMint = await poolLogicProxy.availableManagerFee();
    const tokenPricePreMint = await poolLogicProxy.tokenPrice();
    const totalSupplyPreMint = await poolLogicProxy.totalSupply();
    const managerFeeNumerator = await poolManagerLogicProxy.managerFeeNumerator();
    const streamingFeeNumerator = await poolManagerLogicProxy.streamingFeeNumerator();
    const streamingFee = totalSupplyPreMint
      .mul(ethers.BigNumber.from(await currentBlockTimestamp()).sub(await poolLogicProxy.lastFeeMintTime()))
      .mul(streamingFeeNumerator)
      .div(10000)
      .div(86400 * 365);
    const calculatedAvailableFee =
      tokenPricePreMint > tokenPriceAtLastFeeMint
        ? tokenPricePreMint
            .sub(tokenPriceAtLastFeeMint)
            .mul(totalSupplyPreMint)
            .mul(managerFeeNumerator)
            .div(10000)
            .div(tokenPricePreMint)
            .add(streamingFee)
        : streamingFee;

    expect(streamingFee).lt(calculatedAvailableFee);
    expect(availableFeePreMint).to.be.gt("0");
    checkAlmostSame(availableFeePreMint, calculatedAvailableFee);

    await poolLogicProxy.mintManagerFee();

    const tokenPricePostMint = await poolLogicProxy.tokenPrice();
    const totalSupplyPostMint = await poolLogicProxy.totalSupply();

    checkAlmostSame(totalSupplyPostMint, totalSupplyPreMint.add(availableFeePreMint));
    checkAlmostSame(tokenPricePostMint, tokenPricePreMint.mul(totalSupplyPreMint).div(totalSupplyPostMint));

    checkAlmostSame(
      await poolLogicProxy.balanceOf(dao.address),
      daoBalanceBefore.add(availableFeePreMint.mul(daoFees[0]).div(daoFees[1])),
    );

    const availableFeePostMint = await poolLogicProxy.availableManagerFee();
    expect(availableFeePostMint).to.be.eq("0");
  });

  it("only streaming fee fee after 1 block", async () => {
    const daoFees = await poolFactory.getDaoFee();

    await usdc_price_feed.givenCalldataReturn(
      latestRoundDataABI,
      ethers.utils.solidityPack(
        ["uint256", "int256", "uint256", "uint256", "uint256"],
        [0, 115000000, 0, await currentBlockTimestamp(), 0],
      ),
    ); // $1.15

    await ethers.provider.send("evm_mine", []);

    const daoBalanceBefore = await poolLogicProxy.balanceOf(dao.address);
    const availableFeePreMint = await poolLogicProxy.availableManagerFee();
    const totalSupplyPreMint = await poolLogicProxy.totalSupply();
    const streamingFeeNumerator = await poolManagerLogicProxy.streamingFeeNumerator();

    const streamingFee = totalSupplyPreMint
      .mul(ethers.BigNumber.from(await currentBlockTimestamp()).sub(await poolLogicProxy.lastFeeMintTime()))
      .mul(streamingFeeNumerator)
      .div(10000)
      .div(86400 * 365);
    checkAlmostSame(availableFeePreMint, streamingFee);

    await poolLogicProxy.mintManagerFee();

    checkAlmostSame(
      await poolLogicProxy.balanceOf(dao.address),
      daoBalanceBefore.add(availableFeePreMint.mul(daoFees[0]).div(daoFees[1])),
    );
  });

  it("should mint manager fee after large deposit (1 year after)", async () => {
    const daoFees = await poolFactory.getDaoFee();

    await USDC.approve(poolLogicProxy.address, (200e6).toString());
    await poolLogicProxy.deposit(assets.usdc, (200e6).toString());

    await usdc_price_feed.givenCalldataReturn(
      latestRoundDataABI,
      ethers.utils.solidityPack(
        ["uint256", "int256", "uint256", "uint256", "uint256"],
        [0, 120000000, 0, await currentBlockTimestamp(), 0],
      ),
    ); // $1.2

    await ethers.provider.send("evm_increaseTime", [3600 * 24 * 365]);
    await ethers.provider.send("evm_mine", []);

    const daoBalanceBefore = await poolLogicProxy.balanceOf(dao.address);
    const tokenPriceAtLastFeeMint = await poolLogicProxy.tokenPriceAtLastFeeMint();
    const availableFeePreMint = await poolLogicProxy.availableManagerFee();
    const tokenPricePreMint = await poolLogicProxy.tokenPrice();
    const totalSupplyPreMint = await poolLogicProxy.totalSupply();
    const managerFeeNumerator = await poolManagerLogicProxy.managerFeeNumerator();
    const streamingFeeNumerator = await poolManagerLogicProxy.streamingFeeNumerator();
    const streamingFee = totalSupplyPreMint
      .mul(ethers.BigNumber.from(await currentBlockTimestamp()).sub(await poolLogicProxy.lastFeeMintTime()))
      .mul(streamingFeeNumerator)
      .div(10000)
      .div(86400 * 365);
    const calculatedAvailableFee =
      tokenPricePreMint > tokenPriceAtLastFeeMint
        ? tokenPricePreMint
            .sub(tokenPriceAtLastFeeMint)
            .mul(totalSupplyPreMint)
            .mul(managerFeeNumerator)
            .div(10000)
            .div(tokenPricePreMint)
            .add(streamingFee)
        : streamingFee;

    expect(streamingFee).lt(calculatedAvailableFee);
    expect(availableFeePreMint).to.be.gt("0");
    checkAlmostSame(availableFeePreMint, calculatedAvailableFee);

    await poolLogicProxy.mintManagerFee();

    const tokenPricePostMint = await poolLogicProxy.tokenPrice();
    const totalSupplyPostMint = await poolLogicProxy.totalSupply();

    checkAlmostSame(totalSupplyPostMint, totalSupplyPreMint.add(availableFeePreMint));
    checkAlmostSame(tokenPricePostMint, tokenPricePreMint.mul(totalSupplyPreMint).div(totalSupplyPostMint));

    checkAlmostSame(
      await poolLogicProxy.balanceOf(dao.address),
      daoBalanceBefore.add(availableFeePreMint.mul(daoFees[0]).div(daoFees[1])),
    );

    const availableFeePostMint = await poolLogicProxy.availableManagerFee();
    expect(availableFeePostMint).to.be.eq("0");
  });
});
