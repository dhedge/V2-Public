const { ethers, upgrades } = require("hardhat");
const { expect, use } = require("chai");
const chaiAlmost = require("chai-almost");

use(chaiAlmost());

const checkAlmostSame = (a, b) => {
  expect(ethers.BigNumber.from(a).gt(ethers.BigNumber.from(b).mul(99).div(100))).to.be.true;
  expect(ethers.BigNumber.from(a).lt(ethers.BigNumber.from(b).mul(101).div(100))).to.be.true;
};

const units = (value) => ethers.utils.parseUnits(value.toString());

// sushiswap
const sushiswapV2Factory = "0xc35DADB65012eC5796536bD9864eD8773aBc74C4";
const sushiswapV2Router = "0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506";
const sushiMiniChefV2 = "0x0769fd68dFb93167989C6f7254cd0D766Fb2841F";

// aave
const aaveProtocolDataProvider = "0x7551b5D2763519d4e37e8B81929D336De671d46d";
const aaveLendingPool = "0x8dFf5E27EA6b7AC08EbFdf9eB090F32ee9a30fcf";

// For mainnet
const wmatic = "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270";
const weth = "0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619";
const usdc = "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174";
const usdt = "0xc2132D05D31c914a87C6611C10748AEb04B58e8F";
const sushiToken = "0x0b3F868E0BE5597D5DB7fEB59E1CADBb0fdDa50a";

const amweth = "0x28424507fefb6f7f8E9D3860F56504E4e5f5f390";
const amusdc = "0x1a13F4Ca1d028320A707D99520AbFefca3998b7F";
const amusdt = "0xc2132D05D31c914a87C6611C10748AEb04B58e8F";

const matic_price_feed = "0xAB594600376Ec9fD91F8e885dADF0CE036862dE0";
const eth_price_feed = "0xF9680D99D6C9589e2a93a78A04A279e509205945";
const usdc_price_feed = "0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7";
const usdt_price_feed = "0x0A6513e40db6EB1b165753AD52E80663aeA50545";
const sushi_price_feed = "0x49B0c695039243BBfEb8EcD054EB70061fd54aa0";

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

const sushiLpUsdcWeth = "0x34965ba0ac2451A34a0471F04CCa3F990b8dea27";
const sushiLPUsdcWethPoolId = 1;

describe("Polygon Mainnet Test", function () {
  let WMatic, WETH, USDC, USDT, SushiLPUSDCWETH, SUSHI, AMUSDC;
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

    PoolFactory = await ethers.getContractFactory("PoolFactory");
    poolFactory = await upgrades.deployProxy(PoolFactory, [
      poolLogic.address,
      poolManagerLogic.address,
      ZERO_ADDRESS,
      governance.address,
    ]);
    await poolFactory.deployed();

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
    const assetAmusdc = { asset: amusdc, assetType: 0, aggregator: usdc_price_feed };
    const assetHandlerInitAssets = [
      assetWmatic,
      assetWeth,
      assetUsdt,
      assetUsdc,
      assetSushi,
      assetSushiLPWethUsdc,
      assetAmusdc,
    ];

    assetHandler = await upgrades.deployProxy(AssetHandlerLogic, [poolFactory.address, assetHandlerInitAssets]);
    await assetHandler.deployed();
    await poolFactory.setAssetHandler(assetHandler.address);
    await assetHandler.setChainlinkTimeout((3600 * 24 * 365).toString()); // 1 year expiry

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

    const AaveLendingPoolGuard = await ethers.getContractFactory("AaveLendingPoolGuard");
    aaveLendingPoolGuard = await AaveLendingPoolGuard.deploy(aaveProtocolDataProvider);
    aaveLendingPoolGuard.deployed();

    await governance.setAssetGuard(0, erc20Guard.address);
    await governance.setAssetGuard(2, sushiLPAssetGuard.address);
    await governance.setContractGuard(sushiswapV2Router, uniswapV2RouterGuard.address);
    await governance.setContractGuard(sushiMiniChefV2, sushiMiniChefV2Guard.address);
    await governance.setContractGuard(aaveLendingPool, aaveLendingPoolGuard.address);
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
    AMUSDC = await ethers.getContractAt(IERC20.abi, amusdc);
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

  describe("Aave", () => {
    it("Should be able to deposit usdc and receive amusdc", async () => {
      const amount = (100e6).toString();

      const ILendingPool = await hre.artifacts.readArtifact("ILendingPool");
      const iLendingPool = new ethers.utils.Interface(ILendingPool.abi);
      let depositABI = iLendingPool.encodeFunctionData("deposit", [usdc, amount, poolLogicProxy.address, 0]);

      await expect(poolLogicProxy.connect(manager).execTransaction(ZERO_ADDRESS, depositABI)).to.be.revertedWith(
        "non-zero address is required",
      );

      await expect(
        poolLogicProxy.connect(manager).execTransaction(poolLogicProxy.address, depositABI),
      ).to.be.revertedWith("invalid destination");

      depositABI = iLendingPool.encodeFunctionData("deposit", [amusdt, amount, poolLogicProxy.address, 0]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, depositABI)).to.be.revertedWith(
        "unsupported deposit asset",
      );

      depositABI = iLendingPool.encodeFunctionData("deposit", [usdc, amount, poolLogicProxy.address, 0]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, depositABI)).to.be.revertedWith(
        "unsupported aave interest bearing token",
      );

      // add supported assets
      await poolManagerLogicProxy.connect(manager).changeAssets([[amusdc, false]], []);

      depositABI = iLendingPool.encodeFunctionData("deposit", [usdc, amount, usdc, 0]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, depositABI)).to.be.revertedWith(
        "recipient is not pool",
      );

      depositABI = iLendingPool.encodeFunctionData("deposit", [usdc, amount, poolLogicProxy.address, 0]);
      await expect(poolLogicProxy.connect(manager).execTransaction(usdc, depositABI)).to.be.revertedWith(
        "invalid transaction",
      );

      await expect(poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, depositABI)).to.be.revertedWith(
        "failed to execute the call",
      );

      // approve usdc
      const IERC20 = await hre.artifacts.readArtifact("IERC20");
      const iERC20 = new ethers.utils.Interface(IERC20.abi);
      let approveABI = iERC20.encodeFunctionData("approve", [aaveLendingPool, amount]);
      await poolLogicProxy.connect(manager).execTransaction(usdc, approveABI);

      const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
      const amusdcBalanceBefore = await AMUSDC.balanceOf(poolLogicProxy.address);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      expect(usdcBalanceBefore).to.be.equal((200e6).toString());
      expect(amusdcBalanceBefore).to.be.equal(0);

      // deposit
      await poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, depositABI);

      const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
      const amusdcBalanceAfter = await AMUSDC.balanceOf(poolLogicProxy.address);
      expect(usdcBalanceAfter).to.be.equal((100e6).toString());
      expect(amusdcBalanceAfter).to.be.gte((100e6).toString());

      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
    });

    it("Should be able to withdraw amusdc and receive usdc", async () => {
      const amount = (50e6).toString();

      const ILendingPool = await hre.artifacts.readArtifact("ILendingPool");
      const iLendingPool = new ethers.utils.Interface(ILendingPool.abi);
      let withdrawABI = iLendingPool.encodeFunctionData("withdraw", [usdc, amount, poolLogicProxy.address]);

      await expect(poolLogicProxy.connect(manager).execTransaction(ZERO_ADDRESS, withdrawABI)).to.be.revertedWith(
        "non-zero address is required",
      );

      await expect(
        poolLogicProxy.connect(manager).execTransaction(poolLogicProxy.address, withdrawABI),
      ).to.be.revertedWith("invalid destination");

      withdrawABI = iLendingPool.encodeFunctionData("withdraw", [amusdt, amount, poolLogicProxy.address]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, withdrawABI)).to.be.revertedWith(
        "unsupported withdraw asset",
      );
      withdrawABI = iLendingPool.encodeFunctionData("withdraw", [usdc, amount, usdc]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, withdrawABI)).to.be.revertedWith(
        "recipient is not pool",
      );

      withdrawABI = iLendingPool.encodeFunctionData("withdraw", [usdc, amount, poolLogicProxy.address]);
      await expect(poolLogicProxy.connect(manager).execTransaction(usdc, withdrawABI)).to.be.revertedWith(
        "invalid transaction",
      );

      // await expect(poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, withdrawABI)).to.be.revertedWith(
      //   "failed to execute the call",
      // );

      // // approve usdc
      // const IERC20 = await hre.artifacts.readArtifact("IERC20");
      // const iERC20 = new ethers.utils.Interface(IERC20.abi);
      // let approveABI = iERC20.encodeFunctionData("approve", [aaveLendingPool, amount]);
      // await poolLogicProxy.connect(manager).execTransaction(amusdc, approveABI);

      const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
      const amusdcBalanceBefore = await AMUSDC.balanceOf(poolLogicProxy.address);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      // withdraw
      await poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, withdrawABI);

      const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
      const amusdcBalanceAfter = await AMUSDC.balanceOf(poolLogicProxy.address);
      expect(ethers.BigNumber.from(usdcBalanceBefore).add(amount)).to.be.equal(usdcBalanceAfter);
      expect(ethers.BigNumber.from(amusdcBalanceBefore).sub(amount)).to.be.equal(amusdcBalanceAfter);

      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
    });

    it("Should be able to set reserve as collateral", async () => {
      const ILendingPool = await hre.artifacts.readArtifact("ILendingPool");
      const lendingPool = await ethers.getContractAt(ILendingPool.abi, aaveLendingPool);

      const iLendingPool = new ethers.utils.Interface(ILendingPool.abi);

      let abi = iLendingPool.encodeFunctionData("setUserUseReserveAsCollateral", [usdt, true]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, abi)).to.be.revertedWith(
        "unsupported asset",
      );

      abi = iLendingPool.encodeFunctionData("setUserUseReserveAsCollateral", [weth, true]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, abi)).to.be.revertedWith(
        "unsupported aave interest bearing token",
      );

      abi = iLendingPool.encodeFunctionData("setUserUseReserveAsCollateral", [usdc, false]);
      await poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, abi);

      const userConfigBefore = await lendingPool.getUserConfiguration(poolLogicProxy.address);

      abi = iLendingPool.encodeFunctionData("setUserUseReserveAsCollateral", [usdc, true]);
      await poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, abi);

      const userConfigAfter = await lendingPool.getUserConfiguration(poolLogicProxy.address);
      expect(userConfigBefore).to.be.not.equal(userConfigAfter);
    });
  });
});
