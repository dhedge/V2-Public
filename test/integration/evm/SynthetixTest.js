const { ethers, upgrades } = require("hardhat");
const { expect, use } = require("chai");
const chaiAlmost = require("chai-almost");
const { checkAlmostSame } = require("../../TestHelpers");

use(chaiAlmost());

const uniswapV2Factory = "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f";
const uniswapV2Router = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";

// For mainnet
const susd_price_feed = "0xad35Bd71b9aFE6e4bDc266B345c198eaDEf9Ad94";
const eth_price_feed = "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419";
const link_price_feed = "0x2c1d072e956AFFC0D435Cb7AC38EF18d24d9127c";

const weth = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
const usdc = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
const susd = "0x57Ab1ec28D129707052df4dF418D58a2D46d5f51";
const seth = "0x5e74C9036fb86BD7eCdcb084a0673EFc32eA31cb";
const slink = "0xbBC455cb4F1B9e4bFC4B73970d360c8f032EfEE6";
const susdKey = "0x7355534400000000000000000000000000000000000000000000000000000000";
const sethKey = "0x7345544800000000000000000000000000000000000000000000000000000000";
const slinkKey = "0x734c494e4b000000000000000000000000000000000000000000000000000000";
const addressResolverAddress = "0x823bE81bbF96BEc0e25CA13170F5AaCb5B79ba83";
const synthetixAddress = "0x97767D7D04Fd0dB0A1a2478DCd4BA85290556B48";
const uniswapV2RouterAddress = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

describe("Synthetix Test", function () {
  let WETH, susdProxy, sethProxy, slinkProxy, addressResolver, synthetix, uniswapV2Router;
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
    const assetSusd = { asset: susd, assetType: 0, aggregator: susd_price_feed };
    const assetSeth = { asset: seth, assetType: 0, aggregator: eth_price_feed };
    const assetSlink = { asset: slink, assetType: 0, aggregator: link_price_feed };
    const assetHandlerInitAssets = [assetSusd, assetSeth, assetSlink];

    assetHandler = await upgrades.deployProxy(AssetHandlerLogic, [assetHandlerInitAssets]);
    await assetHandler.deployed();
    await assetHandler.setChainlinkTimeout((3600 * 24 * 365).toString()); // 1 year

    PoolFactory = await ethers.getContractFactory("PoolFactory");
    poolFactory = await upgrades.deployProxy(PoolFactory, [
      poolLogic.address,
      poolManagerLogic.address,
      assetHandler.address,
      dao.address,
      governance.address,
    ]);
    await poolFactory.deployed();

    const IAddressResolver = await hre.artifacts.readArtifact("IAddressResolver");
    addressResolver = await ethers.getContractAt(IAddressResolver.abi, addressResolverAddress);

    const IUniswapV2Router = await hre.artifacts.readArtifact("IUniswapV2Router");
    uniswapV2Router = await ethers.getContractAt(IUniswapV2Router.abi, uniswapV2RouterAddress);

    const ISynthetix = await hre.artifacts.readArtifact("ISynthetix");
    synthetix = await ethers.getContractAt(ISynthetix.abi, synthetixAddress);

    const SynthetixGuard = await ethers.getContractFactory("SynthetixGuard");
    synthetixGuard = await SynthetixGuard.deploy(addressResolver.address);
    synthetixGuard.deployed();

    const ERC20Guard = await ethers.getContractFactory("ERC20Guard");
    erc20Guard = await ERC20Guard.deploy();
    erc20Guard.deployed();

    const UniswapV2RouterGuard = await ethers.getContractFactory("UniswapV2RouterGuard");
    uniswapV2RouterGuard = await UniswapV2RouterGuard.deploy(uniswapV2Factory);
    uniswapV2RouterGuard.deployed();

    await governance.setAssetGuard(0, erc20Guard.address);
    await governance.setContractGuard(uniswapV2Router.address, uniswapV2RouterGuard.address);
    await governance.setContractGuard(synthetix.address, synthetixGuard.address);
  });

  it("Should be able to get susd", async function () {
    const IWETH = await hre.artifacts.readArtifact("IWETH");
    WETH = await ethers.getContractAt(IWETH.abi, weth);

    const ISynthAddressProxy = await hre.artifacts.readArtifact("ISynthAddressProxy");
    susdProxy = await ethers.getContractAt(ISynthAddressProxy.abi, susd);
    sethProxy = await ethers.getContractAt(ISynthAddressProxy.abi, seth);
    slinkProxy = await ethers.getContractAt(ISynthAddressProxy.abi, slink);

    // deposit ETH -> WETH
    await WETH.deposit({ value: (5e18).toString() });
    // WETH -> susd
    await WETH.approve(uniswapV2Router.address, (5e18).toString());
    await uniswapV2Router.swapExactTokensForTokens(
      (5e18).toString(),
      0,
      [weth, susd],
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
        [susd, true],
        [seth, true],
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
          [susd, true],
          [seth, true],
        ],
      ),
    ).to.be.revertedWith("invalid manager fee");

    let tx = await poolFactory.createFund(
      false,
      manager.address,
      "Barren Wuffet",
      "Test Fund",
      "DHTF",
      new ethers.BigNumber.from("5000"),
      [
        [susd, true],
        [seth, true],
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
    expect(await poolManagerLogicProxy.isSupportedAsset(susd)).to.be.true;
    expect(await poolManagerLogicProxy.isSupportedAsset(seth)).to.be.true;

    //Other assets are not supported
    expect(await poolManagerLogicProxy.isSupportedAsset(slink)).to.be.false;
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

    await expect(poolLogicProxy.deposit(slink, (100e18).toString())).to.be.revertedWith("invalid deposit asset");

    await susdProxy.approve(poolLogicProxy.address, (100e18).toString());
    await poolLogicProxy.deposit(susd, (100e18).toString());
    let event = await depositEvent;

    expect(event.fundAddress).to.equal(poolLogicProxy.address);
    expect(event.investor).to.equal(logicOwner.address);
    checkAlmostSame(event.valueDeposited, (100e18).toString());
    checkAlmostSame(event.fundTokensReceived, (100e18).toString());
    checkAlmostSame(event.totalInvestorFundTokens, (100e18).toString());
    checkAlmostSame(event.fundValue, (100e18).toString());
    checkAlmostSame(event.totalSupply, (100e18).toString());
  });

  it("Should be able to approve", async () => {
    const IERC20 = await hre.artifacts.readArtifact("IERC20");
    const iERC20 = new ethers.utils.Interface(IERC20.abi);
    let approveABI = iERC20.encodeFunctionData("approve", [susd, (100e18).toString()]);
    await expect(poolLogicProxy.connect(manager).execTransaction(slink, approveABI)).to.be.revertedWith(
      "asset not enabled in pool",
    );

    await expect(poolLogicProxy.connect(manager).execTransaction(susd, approveABI)).to.be.revertedWith(
      "unsupported spender approval",
    );

    approveABI = iERC20.encodeFunctionData("approve", [synthetix.address, (100e18).toString()]);
    await poolLogicProxy.connect(manager).execTransaction(susd, approveABI);
  });

  it("should be able to swap tokens on synthetix.", async () => {
    let exchangeEvent = new Promise((resolve, reject) => {
      synthetixGuard.on("Exchange", (managerLogicAddress, sourceAsset, sourceAmount, destinationAsset, time, event) => {
        event.removeListener();

        resolve({
          managerLogicAddress: managerLogicAddress,
          sourceAsset: sourceAsset,
          sourceAmount: sourceAmount,
          destinationAsset: destinationAsset,
          time: time,
        });
      });

      setTimeout(() => {
        reject(new Error("timeout"));
      }, 600000);
    });

    const sourceKey = susdKey;
    const sourceAmount = (100e18).toString();
    const destinationKey = sethKey;
    const daoAddress = await poolFactory.getDaoAddress();
    const trackingCode = "0x4448454447450000000000000000000000000000000000000000000000000000"; // DHEDGE

    const ISynthetix = await hre.artifacts.readArtifact("ISynthetix");
    const iSynthetix = new ethers.utils.Interface(ISynthetix.abi);
    let swapABI = iSynthetix.encodeFunctionData("exchangeWithTracking", [
      sourceKey,
      sourceAmount,
      destinationKey,
      daoAddress,
      trackingCode,
    ]);

    await expect(
      poolLogicProxy.connect(manager).execTransaction("0x0000000000000000000000000000000000000000", swapABI),
    ).to.be.revertedWith("non-zero address is required");

    await expect(poolLogicProxy.connect(manager).execTransaction(susd_price_feed, swapABI)).to.be.revertedWith(
      "invalid destination",
    );

    await expect(poolLogicProxy.connect(manager).execTransaction(synthetix.address, "0xaaaaaaaa")).to.be.revertedWith(
      "invalid transaction",
    );

    swapABI = iSynthetix.encodeFunctionData("exchangeWithTracking", [
      slinkKey,
      sourceAmount,
      destinationKey,
      daoAddress,
      trackingCode,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(synthetix.address, swapABI)).to.be.revertedWith(
      "unsupported source asset",
    );

    swapABI = iSynthetix.encodeFunctionData("exchangeWithTracking", [
      sourceKey,
      sourceAmount,
      slinkKey,
      daoAddress,
      trackingCode,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(synthetix.address, swapABI)).to.be.revertedWith(
      "unsupported destination asset",
    );

    swapABI = iSynthetix.encodeFunctionData("exchangeWithTracking", [
      sourceKey,
      sourceAmount,
      destinationKey,
      daoAddress,
      trackingCode,
    ]);
    await poolLogicProxy.connect(manager).execTransaction(synthetix.address, swapABI);

    expect(await sethProxy.balanceOf(poolLogicProxy.address)).to.be.gt(0);

    let event = await exchangeEvent;
    expect(event.sourceAsset).to.equal(susd);
    expect(event.sourceAmount).to.equal((100e18).toString());
    expect(event.destinationAsset).to.equal(seth);
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
    let withdrawAmount = 50e18;

    await expect(poolLogicProxy.withdraw(withdrawAmount.toString())).to.be.revertedWith("cooldown active");

    await ethers.provider.send("evm_increaseTime", [3600 * 24]); // add 1 day
    await ethers.provider.send("evm_mine", []);

    await poolLogicProxy.withdraw(withdrawAmount.toString());

    let event = await withdrawalEvent;
    expect(event.fundAddress).to.equal(poolLogicProxy.address);
    expect(event.investor).to.equal(logicOwner.address);
    checkAlmostSame(event.valueWithdrawn, (50e18).toString());
    checkAlmostSame(event.fundTokensWithdrawn, (50e18).toString());
    checkAlmostSame(event.totalInvestorFundTokens, (50e18).toString());
    checkAlmostSame(event.fundValue, (50e18).toString());
    checkAlmostSame(event.totalSupply, (50e18).toString());
  });
});
