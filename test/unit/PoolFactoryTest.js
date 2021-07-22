const { ethers, upgrades } = require("hardhat");

// Place holder addresses
const KOVAN_ADDRESS_RESOLVER = "0x242a3DF52c375bEe81b1c668741D7c63aF68FDD2";
const TESTNET_DAO = "0xab0c25f17e993F90CaAaec06514A2cc28DEC340b";

const { expect } = require("chai");
const abiCoder = ethers.utils.defaultAbiCoder;

const { updateChainlinkAggregators, currentBlockTimestamp, checkAlmostSame } = require("./TestHelpers");

let logicOwner, manager, dao, user1;
let poolFactory,
  PoolLogic,
  PoolManagerLogic,
  poolLogic,
  poolManagerLogic,
  poolLogicProxy,
  poolManagerLogicProxy,
  fundAddress;
let IERC20, iERC20, IMiniChefV2, iMiniChefV2;
let synthetixGuard, uniswapV2RouterGuard, uniswapV3SwapGuard, sushiMiniChefV2Guard; // contract guards
let erc20Guard, sushiLPAssetGuard; // asset guards
let addressResolver, synthetix, uniswapV2Router, uniswapV3Router; // integrating contracts
let susd, seth, slink;
let susdAsset, susdProxy, sethAsset, sethProxy, slinkAsset, slinkProxy;
let sushiLPAggregator; // local aggregators
let usd_price_feed, eth_price_feed, link_price_feed; // integrating aggregators

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
const _SYNTHETIX_KEY = "0x53796e7468657469780000000000000000000000000000000000000000000000"; // Synthetix
const _EXCHANGE_RATES_KEY = "0x45786368616e6765526174657300000000000000000000000000000000000000"; // ExchangeRates

const susdKey = "0x7355534400000000000000000000000000000000000000000000000000000000";
const sethKey = "0x7345544800000000000000000000000000000000000000000000000000000000";
const slinkKey = "0x734c494e4b000000000000000000000000000000000000000000000000000000";

const ONE_TOKEN = "1000000000000000000";
const FIVE_TOKENS = "5000000000000000000";
const TEN_TOKENS = "10000000000000000000";
const TWENTY_TOKENS = "20000000000000000000";
const ONE_HUNDRED_TOKENS = "100000000000000000000";

describe("PoolFactory", function () {
  before(async function () {
    [logicOwner, manager, dao, investor, user1, user2, user3, user4] = await ethers.getSigners();

    const MockContract = await ethers.getContractFactory("MockContract");
    addressResolver = await MockContract.deploy();
    synthetix = await MockContract.deploy();
    uniswapV2Router = await MockContract.deploy();
    uniswapV3Router = await MockContract.deploy();
    sushiMiniChefV2 = await MockContract.deploy();
    susdAsset = await MockContract.deploy();
    susdProxy = await MockContract.deploy();
    sethAsset = await MockContract.deploy();
    sethProxy = await MockContract.deploy();
    slinkAsset = await MockContract.deploy();
    slinkProxy = await MockContract.deploy();
    sushiLPLinkWethAsset = await MockContract.deploy();
    usd_price_feed = await MockContract.deploy();
    eth_price_feed = await MockContract.deploy();
    link_price_feed = await MockContract.deploy();
    uniswapV2Factory = await MockContract.deploy();
    sushiToken = await MockContract.deploy();
    wmaticToken = await MockContract.deploy();
    susd = susdProxy.address;
    seth = sethProxy.address;
    slink = slinkProxy.address;
    sushiLPLinkWeth = sushiLPLinkWethAsset.address;
    sushiLPLinkWethPoolId = 1; // set Sushi LP staking contract Pool Id
    badtoken = "0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB";

    // mock IAddressResolver
    const IAddressResolver = await hre.artifacts.readArtifact("IAddressResolver");
    const iAddressResolver = new ethers.utils.Interface(IAddressResolver.abi);
    let getAddressABI = iAddressResolver.encodeFunctionData("getAddress", [_SYNTHETIX_KEY]);
    await addressResolver.givenCalldataReturnAddress(getAddressABI, synthetix.address);

    // mock Sushi LINK-WETH LP
    const IUniswapV2Pair = await hre.artifacts.readArtifact("IUniswapV2Pair");
    const iUniswapV2Pair = new ethers.utils.Interface(IUniswapV2Pair.abi);
    const token0Abi = iUniswapV2Pair.encodeFunctionData("token0", []);
    await sushiLPLinkWethAsset.givenCalldataReturnAddress(token0Abi, slink);
    const token1Abi = iUniswapV2Pair.encodeFunctionData("token1", []);
    await sushiLPLinkWethAsset.givenCalldataReturnAddress(token1Abi, seth);
    const totalSupply = iUniswapV2Pair.encodeFunctionData("totalSupply", []);
    await sushiLPLinkWethAsset.givenCalldataReturnUint(totalSupply, "81244364124268806526393");
    const getReserves = iUniswapV2Pair.encodeFunctionData("getReserves", []);
    await sushiLPLinkWethAsset.givenCalldataReturn(
      getReserves,
      abiCoder.encode(
        ["uint112", "uint112", "uint32"],
        ["1158679007401429485290646", "11024994840258089037095", await currentBlockTimestamp()],
      ),
    );

    // mock ISynthetix
    const ISynthetix = await hre.artifacts.readArtifact("ISynthetix");
    const iSynthetix = new ethers.utils.Interface(ISynthetix.abi);
    let synthsABI = iSynthetix.encodeFunctionData("synths", [susdKey]);
    await synthetix.givenCalldataReturnAddress(synthsABI, susdAsset.address);
    synthsABI = iSynthetix.encodeFunctionData("synths", [sethKey]);
    await synthetix.givenCalldataReturnAddress(synthsABI, sethAsset.address);
    synthsABI = iSynthetix.encodeFunctionData("synths", [slinkKey]);
    await synthetix.givenCalldataReturnAddress(synthsABI, slinkAsset.address);

    let synthsByAddressABI = iSynthetix.encodeFunctionData("synthsByAddress", [susdAsset.address]);
    await synthetix.givenCalldataReturn(synthsByAddressABI, susdKey);
    synthsByAddressABI = iSynthetix.encodeFunctionData("synthsByAddress", [sethAsset.address]);
    await synthetix.givenCalldataReturn(synthsByAddressABI, sethKey);
    synthsByAddressABI = iSynthetix.encodeFunctionData("synthsByAddress", [slinkAsset.address]);
    await synthetix.givenCalldataReturn(synthsByAddressABI, slinkKey);

    // mock ISynth
    const ISynth = await hre.artifacts.readArtifact("ISynth");
    const iSynth = new ethers.utils.Interface(ISynth.abi);
    const proxyABI = iSynth.encodeFunctionData("proxy", []);
    await susdAsset.givenCalldataReturnAddress(proxyABI, susdProxy.address);
    await sethAsset.givenCalldataReturnAddress(proxyABI, sethProxy.address);
    await slinkAsset.givenCalldataReturnAddress(proxyABI, slinkProxy.address);

    // mock ISynthAddressProxy
    const ISynthAddressProxy = await hre.artifacts.readArtifact("ISynthAddressProxy");
    const iSynthAddressProxy = new ethers.utils.Interface(ISynthAddressProxy.abi);
    const targetABI = iSynthAddressProxy.encodeFunctionData("target", []);
    await susdProxy.givenCalldataReturnAddress(targetABI, susdAsset.address);
    await sethProxy.givenCalldataReturnAddress(targetABI, sethAsset.address);
    await slinkProxy.givenCalldataReturnAddress(targetABI, slinkAsset.address);

    // mock sushiMiniChefV2
    const IMiniChefV2 = await hre.artifacts.readArtifact("IMiniChefV2");
    const iMiniChefV2 = new ethers.utils.Interface(IMiniChefV2.abi);
    const poolLengthABI = iMiniChefV2.encodeFunctionData("poolLength", []);
    await sushiMiniChefV2.givenCalldataReturnUint(poolLengthABI, "1");
    const lpTokenABI = iMiniChefV2.encodeFunctionData("lpToken", [sushiLPLinkWethPoolId]);
    await sushiMiniChefV2.givenCalldataReturnAddress(lpTokenABI, sushiLPLinkWeth);

    IERC20 = await hre.artifacts.readArtifact("ERC20Upgradeable");
    iERC20 = new ethers.utils.Interface(IERC20.abi);
    let decimalsABI = iERC20.encodeFunctionData("decimals", []);
    await susdProxy.givenCalldataReturnUint(decimalsABI, "18");
    await sethProxy.givenCalldataReturnUint(decimalsABI, "18");
    await slinkProxy.givenCalldataReturnUint(decimalsABI, "18");
    await sushiLPLinkWethAsset.givenCalldataReturnUint(decimalsABI, "18");
    await sushiToken.givenCalldataReturnUint(decimalsABI, "18");
    await wmaticToken.givenCalldataReturnUint(decimalsABI, "18");

    // Aggregators
    await updateChainlinkAggregators(usd_price_feed, eth_price_feed, link_price_feed);

    // Deploy Sushi LP Aggregator
    const SushiLPAggregator = await ethers.getContractFactory("SushiLPAggregator");
    sushiLPAggregator = await SushiLPAggregator.deploy(
      sushiLPLinkWeth,
      link_price_feed.address,
      eth_price_feed.address,
    );

    const Governance = await ethers.getContractFactory("Governance");
    let governance = await Governance.deploy();
    console.log("governance deployed to:", governance.address);

    PoolLogic = await ethers.getContractFactory("PoolLogic");
    poolLogic = await PoolLogic.deploy();

    PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
    poolManagerLogic = await PoolManagerLogic.deploy();

    // Initialize Asset Price Consumer
    const assetSusd = { asset: susd, assetType: 0, aggregator: usd_price_feed.address };
    const assetSeth = { asset: seth, assetType: 0, aggregator: eth_price_feed.address };
    const assetSlink = { asset: slink, assetType: 0, aggregator: link_price_feed.address };
    const assetSushi = { asset: sushiToken.address, assetType: 0, aggregator: usd_price_feed.address }; // just peg price to USD
    const assetWmatic = { asset: wmaticToken.address, assetType: 0, aggregator: usd_price_feed.address }; // just peg price to USD
    const assetSushiLPLinkWeth = { asset: sushiLPLinkWeth, assetType: 2, aggregator: sushiLPAggregator.address };
    const assetHandlerInitAssets = [assetSusd, assetSeth, assetSlink, assetSushi, assetWmatic, assetSushiLPLinkWeth];

    // await assetHandler.initialize(poolFactoryProxy.address, assetHandlerInitAssets);
    // await assetHandler.deployed();
    AssetHandlerLogic = await ethers.getContractFactory("AssetHandler");
    assetHandler = await upgrades.deployProxy(AssetHandlerLogic, [assetHandlerInitAssets]);
    await assetHandler.deployed();
    console.log("assetHandler deployed to:", assetHandler.address);

    const PoolFactoryLogic = await ethers.getContractFactory("PoolFactory");
    poolFactory = await upgrades.deployProxy(PoolFactoryLogic, [
      poolLogic.address,
      poolManagerLogic.address,
      assetHandler.address,
      dao.address,
      governance.address,
    ]);
    await poolFactory.deployed();
    console.log("poolFactory deployed to:", poolFactory.address);

    // Initialise pool factory
    // await poolFactory.initialize(poolLogic.address, poolManagerLogic.address, assetHandlerProxy.address, dao.address);
    // await poolFactory.deployed();

    // Deploy contract guards
    const SynthetixGuard = await ethers.getContractFactory("SynthetixGuard");
    synthetixGuard = await SynthetixGuard.deploy(addressResolver.address);
    synthetixGuard.deployed();

    const UniswapV2RouterGuard = await ethers.getContractFactory("UniswapV2RouterGuard");
    uniswapV2RouterGuard = await UniswapV2RouterGuard.deploy(uniswapV2Factory.address);
    uniswapV2RouterGuard.deployed();

    const UniswapV3SwapGuard = await ethers.getContractFactory("UniswapV3SwapGuard");
    uniswapV3SwapGuard = await UniswapV3SwapGuard.deploy();
    uniswapV3SwapGuard.deployed();

    const SushiMiniChefV2Guard = await ethers.getContractFactory("SushiMiniChefV2Guard");
    sushiMiniChefV2Guard = await SushiMiniChefV2Guard.deploy(sushiToken.address, wmaticToken.address);
    sushiMiniChefV2Guard.deployed();

    // Deploy asset guards
    const ERC20Guard = await ethers.getContractFactory("ERC20Guard");
    erc20Guard = await ERC20Guard.deploy();
    erc20Guard.deployed();

    const SushiLPAssetGuard = await ethers.getContractFactory("SushiLPAssetGuard");
    sushiLPAssetGuard = await SushiLPAssetGuard.deploy(sushiMiniChefV2.address); // initialise with Sushi staking pool Id
    sushiLPAssetGuard.deployed();

    await governance.setAssetGuard(0, erc20Guard.address);
    await governance.setAssetGuard(2, sushiLPAssetGuard.address);
    await governance.setContractGuard(synthetix.address, synthetixGuard.address);
    await governance.setContractGuard(uniswapV2Router.address, uniswapV2RouterGuard.address);
    await governance.setContractGuard(uniswapV3Router.address, uniswapV3SwapGuard.address);
    await governance.setContractGuard(sushiMiniChefV2.address, sushiMiniChefV2Guard.address);
  });

  it("Should be able to createFund", async function () {
    await poolLogic.initialize(poolFactory.address, false, "Test Fund", "DHTF");

    console.log("Passed poolLogic Init!");

    await poolManagerLogic.initialize(poolFactory.address, manager.address, "Barren Wuffet", poolLogic.address, [
      [susd, true],
      [seth, true],
    ]);

    console.log("Passed poolManagerLogic Init!");

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
    ).to.be.revertedWith("invalid fraction");

    console.log("Creating Fund...");

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
          [susd, false],
          [seth, true],
        ],
      ),
    ).to.be.revertedWith("invalid fraction");

    await expect(
      poolFactory.createFund(
        false,
        manager.address,
        "Barren Wuffet",
        "Test Fund",
        "DHTF",
        new ethers.BigNumber.from("5000"),
        [
          [susd, false],
          [seth, false],
        ],
      ),
    ).to.be.revertedWith("Implementation init failed"); // at least one deposit asset

    await poolFactory.createFund(
      false,
      manager.address,
      "Barren Wuffet",
      "Test Fund",
      "DHTF",
      new ethers.BigNumber.from("5000"),
      [
        [seth, false],
        [susd, true],
      ],
    );

    let event = await fundCreatedEvent;

    fundAddress = event.fundAddress;
    console.log("fundAddress: ", fundAddress);
    expect(event.isPoolPrivate).to.be.false;
    expect(event.fundName).to.equal("Test Fund");
    // expect(event.fundSymbol).to.equal('DHTF');
    expect(event.managerName).to.equal("Barren Wuffet");
    expect(event.manager).to.equal(manager.address);
    expect(event.managerFeeNumerator.toString()).to.equal("5000");
    expect(event.managerFeeDenominator.toString()).to.equal("10000");

    let deployedFunds = await poolFactory.getDeployedFunds();
    let deployedFundsLength = deployedFunds.length;
    expect(deployedFundsLength).to.equal(1);

    let isPool = await poolFactory.isPool(fundAddress);
    expect(isPool).to.be.true;

    let poolManagerLogicAddress = await poolFactory.getLogic(1);
    expect(poolManagerLogicAddress).to.equal(poolManagerLogic.address);

    let poolLogicAddress = await poolFactory.getLogic(2);
    expect(poolLogicAddress).to.equal(poolLogic.address);

    poolLogicProxy = await PoolLogic.attach(fundAddress);
    let poolManagerLogicProxyAddress = await poolLogicProxy.poolManagerLogic();
    poolManagerLogicProxy = await PoolManagerLogic.attach(poolManagerLogicProxyAddress);

    // check create fund works correctly for AssetAdded event (fundAddress = poolLogic)
    expect(poolManagerLogicProxy.filters.AssetAdded(poolLogicProxy.address).topics[1]).to.be.equal(
      ethers.utils.hexZeroPad(poolLogicProxy.address, 32).toLowerCase(),
    );

    //default assets are supported
    let supportedAssets = await poolManagerLogicProxy.getSupportedAssets();
    expect(supportedAssets.length).to.equal(2);
    expect(await poolManagerLogicProxy.isSupportedAsset(susd)).to.be.true;
    expect(await poolManagerLogicProxy.isSupportedAsset(seth)).to.be.true;

    //Other assets are not supported
    expect(await poolManagerLogicProxy.isSupportedAsset(slink)).to.be.false;

    // mock IMiniChefV2
    IMiniChefV2 = await hre.artifacts.readArtifact("IMiniChefV2");
    iMiniChefV2 = new ethers.utils.Interface(IMiniChefV2.abi);
    const userInfo = iMiniChefV2.encodeFunctionData("userInfo", [sushiLPLinkWethPoolId, poolLogicProxy.address]);
    const amountLPStaked = "0";
    const amountRewarded = "0";
    await sushiMiniChefV2.givenCalldataReturn(
      userInfo,
      abiCoder.encode(["uint256", "uint256"], [amountLPStaked, amountRewarded]),
    );
    const lpToken = iMiniChefV2.encodeFunctionData("lpToken", [sushiLPLinkWethPoolId]);
    await sushiMiniChefV2.givenCalldataReturn(lpToken, abiCoder.encode(["address"], [sushiLPLinkWeth]));
  });

  it("should return correct values ", async function () {
    let supportedAssets = await poolManagerLogicProxy.getSupportedAssets();
    let numberOfSupportedAssets = supportedAssets.length;
    let depositAssets = await poolManagerLogicProxy.getDepositAssets();
    let numberOfDepositAssets = depositAssets.length;
    expect(numberOfSupportedAssets).to.gte(numberOfDepositAssets);
    expect(depositAssets[0]).to.eq(susd);
    let fundComposition = await poolManagerLogicProxy.getFundComposition();
    expect(fundComposition.assets.length).to.eq(numberOfSupportedAssets);
    expect(fundComposition.balances.length).to.eq(numberOfSupportedAssets);
    expect(fundComposition.rates.length).to.eq(numberOfSupportedAssets);
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
    let transferFromABI = iERC20.encodeFunctionData("transferFrom", [
      investor.address,
      poolLogicProxy.address,
      (100e18).toString(),
    ]);
    await susdProxy.givenCalldataReturnBool(transferFromABI, true);

    let totalFundValue = await poolManagerLogicProxy.totalFundValue();
    // As default there's susd and seth and each return 1 by IExchangeRates
    expect(totalFundValue.toString()).to.equal("0");

    await expect(poolLogicProxy.deposit(slink, (100e18).toString())).to.be.revertedWith("invalid deposit asset");
    await poolLogicProxy.connect(investor).deposit(susd, (100e18).toString());
    let event = await depositEvent;

    expect(event.fundAddress).to.equal(poolLogicProxy.address);
    expect(event.investor).to.equal(investor.address);
    expect(event.assetDeposited).to.equal(susd);
    expect(event.amountDeposited).to.equal((100e18).toString());
    expect(event.valueDeposited).to.equal((100e18).toString());
    expect(event.fundTokensReceived).to.equal((100e18).toString());
    expect(event.totalInvestorFundTokens).to.equal((100e18).toString());
    expect(event.fundValue).to.equal((100e18).toString());
    expect(event.totalSupply).to.equal((100e18).toString());
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

    // mock sUSD balance
    let balanceOfABI = iERC20.encodeFunctionData("balanceOf", [poolLogicProxy.address]);
    await susdProxy.givenCalldataReturnUint(balanceOfABI, (100e18).toString());

    // Withdraw 50%
    let withdrawAmount = 50e18;
    let totalSupply = await poolLogicProxy.totalSupply();
    let totalFundValue = await poolManagerLogicProxy.totalFundValue();

    await expect(poolLogicProxy.connect(investor).withdraw(withdrawAmount.toString())).to.be.revertedWith(
      "cooldown active",
    );

    // await poolFactory.setExitCooldown(0);
    ethers.provider.send("evm_increaseTime", [3600 * 24]); // add 1 day

    await poolLogicProxy.connect(investor).withdraw(withdrawAmount.toString());

    // let [exitFeeNumerator, exitFeeDenominator] = await poolFactory.getExitFee()
    // let daoExitFee = withdrawAmount * exitFeeNumerator / exitFeeDenominator

    let event = await withdrawalEvent;

    let fundTokensWithdrawn = withdrawAmount;
    let valueWithdrawn = (fundTokensWithdrawn / totalSupply) * totalFundValue;
    expect(event.fundAddress).to.equal(poolLogicProxy.address);
    expect(event.investor).to.equal(investor.address);
    expect(event.valueWithdrawn).to.equal(valueWithdrawn.toString());
    expect(event.fundTokensWithdrawn).to.equal(fundTokensWithdrawn.toString());
    expect(event.totalInvestorFundTokens).to.equal((50e18).toString());
    expect(event.fundValue).to.equal((totalFundValue - valueWithdrawn).toString());
    expect(event.totalSupply).to.equal((100e18 - fundTokensWithdrawn).toString());
    let withdrawnAsset = event.withdrawnAssets[0];
    expect(withdrawnAsset[0]).to.equal(susd);
    expect(withdrawnAsset[1].toString()).to.equal(withdrawAmount.toString());
    expect(withdrawnAsset[2]).to.equal(false);
  });

  it("should be able to manage pool", async function () {
    await poolFactory.createFund(
      true,
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

    let deployedFunds = await poolFactory.getDeployedFunds();
    let deployedFundsLength = deployedFunds.length;
    let fundAddress = deployedFunds[deployedFundsLength - 1];
    let poolLogicPrivateProxy = await PoolLogic.attach(fundAddress);
    let poolManagerLogicPrivateProxy = await PoolManagerLogic.attach(await poolLogicPrivateProxy.poolManagerLogic());

    let transferFromABI = iERC20.encodeFunctionData("transferFrom", [
      investor.address,
      poolLogicPrivateProxy.address,
      (100e18).toString(),
    ]);
    await susdProxy.givenMethodReturnBool(transferFromABI, true);

    // Can't deposit when not being a member
    await expect(poolLogicPrivateProxy.deposit(susd, (100e18).toString())).to.be.revertedWith("only members allowed");

    await expect(poolManagerLogicPrivateProxy.addMember(logicOwner.address)).to.be.revertedWith("only manager");

    let poolLogicPrivateManagerProxy = poolLogicPrivateProxy.connect(manager);
    let poolManagerLogicPrivateManagerProxy = poolManagerLogicPrivateProxy.connect(manager);

    // Can deposit after being a member
    await poolManagerLogicPrivateManagerProxy.addMember(logicOwner.address);

    await poolLogicPrivateProxy.deposit(susd, (100e18).toString());

    // Can't deposit after being removed from a member
    await poolManagerLogicPrivateManagerProxy.removeMember(logicOwner.address);

    await expect(poolLogicPrivateProxy.deposit(susd, (100e18).toString())).to.be.revertedWith("only members allowed");

    // Can set trader
    await expect(poolManagerLogicPrivateProxy.setTrader(user1.address)).to.be.revertedWith("only manager");

    await poolManagerLogicPrivateManagerProxy.setTrader(user1.address);

    // Can remove trader
    await expect(poolManagerLogicPrivateProxy.removeTrader()).to.be.revertedWith("only manager");

    await poolManagerLogicPrivateManagerProxy.removeTrader();

    // Can change manager
    await poolManagerLogicPrivateManagerProxy.changeManager(user1.address, "User1");

    await expect(poolManagerLogicPrivateProxy.changeManager(logicOwner.address, "Logic Owner")).to.be.revertedWith(
      "only manager",
    );
  });

  it("should be able to manage assets", async function () {
    await expect(poolManagerLogicProxy.changeAssets([[slink, false]], [])).to.be.revertedWith("only manager or trader");

    let poolManagerLogicManagerProxy = poolManagerLogicProxy.connect(manager);
    let poolManagerLogicUser1Proxy = poolManagerLogicProxy.connect(user1);

    // Can add asset
    await poolManagerLogicManagerProxy.changeAssets([[slink, false]], []);

    let supportedAssets = await poolManagerLogicManagerProxy.getSupportedAssets();
    let numberOfSupportedAssets = supportedAssets.length;
    expect(numberOfSupportedAssets).to.eq(3);

    depositAssets = await poolManagerLogicManagerProxy.getDepositAssets();
    numberOfDepositAssets = depositAssets.length;
    expect(numberOfDepositAssets).to.be.equal(1);

    // Can not remove persist asset
    await expect(poolManagerLogicUser1Proxy.changeAssets([], [slink])).to.be.revertedWith("only manager or trader");

    // Can't add invalid asset
    let invalid_synth_asset = "0x823bE81bbF96BEc0e25CA13170F5AaCb5B79ba83";
    await expect(poolManagerLogicManagerProxy.changeAssets([[invalid_synth_asset, false]], [])).to.be.revertedWith(
      "invalid asset",
    );

    // Can't remove asset with non zero balance
    // mock IERC20 balanceOf to return non zero
    let balanceOfABI = iERC20.encodeFunctionData("balanceOf", [poolLogicProxy.address]);
    await slinkProxy.givenCalldataReturnUint(balanceOfABI, 1);

    await expect(poolManagerLogicManagerProxy.changeAssets([], [slink])).to.be.revertedWith(
      "revert cannot remove non-empty asset",
    );

    // Can enable deposit asset
    await poolManagerLogicManagerProxy.changeAssets([[slink, true]], []);
    expect(await poolManagerLogicProxy.isDepositAsset(slink)).to.be.true;

    depositAssets = await poolManagerLogicManagerProxy.getDepositAssets();
    numberOfDepositAssets = depositAssets.length;
    expect(numberOfDepositAssets).to.be.equal(2);

    // Can disable deposit asset
    await poolManagerLogicManagerProxy.changeAssets([[slink, false]], []);
    expect(await poolManagerLogicProxy.isDepositAsset(slink)).to.be.false;

    depositAssets = await poolManagerLogicManagerProxy.getDepositAssets();
    numberOfDepositAssets = depositAssets.length;
    expect(numberOfDepositAssets).to.be.equal(1);

    // Can remove asset
    await slinkProxy.givenCalldataReturnUint(balanceOfABI, 0);
    await poolManagerLogicManagerProxy.changeAssets([], [slink]);

    supportedAssets = await poolManagerLogicManagerProxy.getSupportedAssets();
    numberOfSupportedAssets = supportedAssets.length;
    expect(numberOfSupportedAssets).to.eq(2);
  });

  it("should be able to manage fees", async function () {
    //Can't set manager fee if not manager or if fee too high
    await expect(poolManagerLogicProxy.announceManagerFeeIncrease(4000)).to.be.revertedWith("only manager");

    let poolManagerLogicManagerProxy = poolManagerLogicProxy.connect(manager);

    await expect(poolManagerLogicManagerProxy.announceManagerFeeIncrease(6100)).to.be.revertedWith(
      "exceeded allowed increase",
    );

    //Can set manager fee
    await poolManagerLogicManagerProxy.announceManagerFeeIncrease(4000);

    await expect(poolManagerLogicManagerProxy.commitManagerFeeIncrease()).to.be.revertedWith(
      "fee increase delay active",
    );

    ethers.provider.send("evm_increaseTime", [3600 * 24 * 7 * 4]); // add 1 day

    await poolManagerLogicManagerProxy.commitManagerFeeIncrease();

    let [managerFeeNumerator, managerFeeDenominator] = await poolManagerLogicManagerProxy.getManagerFee();
    expect(managerFeeNumerator.toString()).to.equal("4000");
    expect(managerFeeDenominator.toString()).to.equal("10000");

    await expect(poolManagerLogicProxy.setManagerFeeNumerator(3000)).to.be.revertedWith("only manager");
    await expect(poolManagerLogicManagerProxy.setManagerFeeNumerator(5000)).to.be.revertedWith("manager fee too high");
    await poolManagerLogicManagerProxy.setManagerFeeNumerator(3000);
    [managerFeeNumerator, managerFeeDenominator] = await poolManagerLogicManagerProxy.getManagerFee();
    expect(managerFeeNumerator.toString()).to.equal("3000");
    expect(managerFeeDenominator.toString()).to.equal("10000");
  });

  // Synthetix transaction guard
  it("Only manager or trader can execute transaction", async () => {
    await expect(
      poolLogicProxy.connect(logicOwner).execTransaction(synthetix.address, "0x00000000"),
    ).to.be.revertedWith("only manager or trader");
  });

  it("Should fail with invalid destination", async () => {
    await expect(
      poolLogicProxy.connect(manager).execTransaction(poolManagerLogicProxy.address, "0x00000000"),
    ).to.be.revertedWith("invalid destination");
  });

  it("Should exec transaction", async () => {
    let poolLogicManagerProxy = poolLogicProxy.connect(manager);

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
      }, 60000);
    });

    const sourceKey = susdKey;
    const sourceAmount = (100e18).toString();
    const destinationKey = sethKey;
    const daoAddress = await poolFactory.owner();
    const trackingCode = await poolFactory.getTrackingCode();

    const ISynthetix = await hre.artifacts.readArtifact("ISynthetix");
    const iSynthetix = new ethers.utils.Interface(ISynthetix.abi);
    const exchangeWithTrackingABI = iSynthetix.encodeFunctionData("exchangeWithTracking", [
      sourceKey,
      sourceAmount,
      destinationKey,
      daoAddress,
      trackingCode,
    ]);

    await synthetix.givenCalldataRevert(exchangeWithTrackingABI);

    await expect(poolLogicManagerProxy.execTransaction(synthetix.address, exchangeWithTrackingABI)).to.be.revertedWith(
      "failed to execute the call",
    );

    await synthetix.givenCalldataReturnUint(exchangeWithTrackingABI, (1e18).toString());
    await poolLogicManagerProxy.execTransaction(synthetix.address, exchangeWithTrackingABI);

    let event = await exchangeEvent;
    expect(event.sourceAsset).to.equal(susd);
    expect(event.sourceAmount).to.equal((100e18).toString());
    expect(event.destinationAsset).to.equal(seth);
  });

  it("Should be able to approve", async () => {
    let approveABI = iERC20.encodeFunctionData("approve", [susd, (100e18).toString()]);
    await expect(poolLogicProxy.connect(manager).execTransaction(slink, approveABI)).to.be.revertedWith(
      "asset not enabled in pool",
    );

    await expect(poolLogicProxy.connect(manager).execTransaction(susd, approveABI)).to.be.revertedWith(
      "unsupported spender approval",
    );

    approveABI = iERC20.encodeFunctionData("approve", [uniswapV2Router.address, (100e18).toString()]);
    await susdAsset.givenCalldataReturnBool(approveABI, true);
    await poolLogicProxy.connect(manager).execTransaction(susd, approveABI);
  });

  it("should be able to swap tokens on Uniswap v2", async () => {
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

    const sourceAmount = (100e18).toString();
    const IUniswapV2Router = await hre.artifacts.readArtifact("IUniswapV2Router");
    const iUniswapV2Router = new ethers.utils.Interface(IUniswapV2Router.abi);
    let swapABI = iUniswapV2Router.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      0,
      [susd, seth],
      poolManagerLogicProxy.address,
      0,
    ]);

    await expect(poolLogicProxy.connect(manager).execTransaction(ZERO_ADDRESS, swapABI)).to.be.revertedWith(
      "non-zero address is required",
    );

    swapABI = iUniswapV2Router.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      0,
      [slink, seth],
      poolLogicProxy.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(susd, swapABI)).to.be.revertedWith(
      "invalid transaction",
    );

    swapABI = iUniswapV2Router.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      0,
      [slink, seth],
      poolLogicProxy.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(uniswapV2Router.address, swapABI)).to.be.revertedWith(
      "unsupported source asset",
    );

    swapABI = iUniswapV2Router.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      0,
      [susd, user1.address, seth],
      poolLogicProxy.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(uniswapV2Router.address, swapABI)).to.be.revertedWith(
      "invalid routing asset",
    );

    swapABI = iUniswapV2Router.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      0,
      [susd, seth, slink],
      poolLogicProxy.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(uniswapV2Router.address, swapABI)).to.be.revertedWith(
      "unsupported destination asset",
    );

    swapABI = iUniswapV2Router.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      0,
      [susd, seth],
      user1.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(uniswapV2Router.address, swapABI)).to.be.revertedWith(
      "recipient is not pool",
    );

    swapABI = iUniswapV2Router.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      0,
      [susd, seth],
      poolLogicProxy.address,
      0,
    ]);
    await uniswapV2Router.givenCalldataRevert(swapABI);
    await expect(poolLogicProxy.connect(manager).execTransaction(uniswapV2Router.address, swapABI)).to.be.revertedWith(
      "failed to execute the call",
    );

    await uniswapV2Router.givenCalldataReturn(swapABI, []);
    await poolLogicProxy.connect(manager).execTransaction(uniswapV2Router.address, swapABI);

    let event = await exchangeEvent;
    expect(event.sourceAsset).to.equal(susd);
    expect(event.sourceAmount).to.equal((100e18).toString());
    expect(event.destinationAsset).to.equal(seth);
  });

  it("should be able to swap tokens on Uniswap v3 - direct swap", async () => {
    let exchangeEvent = new Promise((resolve, reject) => {
      uniswapV3SwapGuard.on(
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

    const sourceAmount = (100e18).toString();
    const IUniswapV3Router = await hre.artifacts.readArtifact("IUniswapV3Router");
    const iUniswapV3Router = new ethers.utils.Interface(IUniswapV3Router.abi);
    const exactInputSingleParams = {
      tokenIn: susd,
      tokenOut: seth,
      fee: 10000,
      recipient: poolManagerLogicProxy.address,
      deadline: 1,
      amountIn: sourceAmount,
      amountOutMinimum: 0,
      sqrtPriceLimitX96: 0,
    };
    let badExactInputSingleParams = exactInputSingleParams;

    // fail to swap direct asset to asset because it is interaction is with 0x0 address
    let swapABI = iUniswapV3Router.encodeFunctionData("exactInputSingle", [exactInputSingleParams]);
    await expect(poolLogicProxy.connect(manager).execTransaction(ZERO_ADDRESS, swapABI)).to.be.revertedWith(
      "non-zero address is required",
    );

    // fail to swap direct asset to asset because unsupported source asset
    badExactInputSingleParams.tokenIn = slink;
    swapABI = iUniswapV3Router.encodeFunctionData("exactInputSingle", [badExactInputSingleParams]);
    await expect(poolLogicProxy.connect(manager).execTransaction(uniswapV3Router.address, swapABI)).to.be.revertedWith(
      "unsupported source asset",
    );
    badExactInputSingleParams.tokenIn = susd;

    // fail to swap direct asset to asset because unsupported destination asset
    badExactInputSingleParams.tokenOut = slink;
    swapABI = iUniswapV3Router.encodeFunctionData("exactInputSingle", [badExactInputSingleParams]);
    await expect(poolLogicProxy.connect(manager).execTransaction(uniswapV3Router.address, swapABI)).to.be.revertedWith(
      "unsupported destination asset",
    );
    badExactInputSingleParams.tokenOut = seth;

    // fail to swap direct asset to asset because recipient is not the pool address
    badExactInputSingleParams.recipient = user1.address;
    swapABI = iUniswapV3Router.encodeFunctionData("exactInputSingle", [badExactInputSingleParams]);
    await expect(poolLogicProxy.connect(manager).execTransaction(uniswapV3Router.address, swapABI)).to.be.revertedWith(
      "recipient is not pool",
    );
    exactInputSingleParams.recipient = poolLogicProxy.address;

    // succeed swapping direct asset to asset
    await uniswapV3Router.givenCalldataReturn(swapABI, []);
    swapABI = iUniswapV3Router.encodeFunctionData("exactInputSingle", [exactInputSingleParams]);
    await poolLogicProxy.connect(manager).execTransaction(uniswapV3Router.address, swapABI);

    let event = await exchangeEvent;
    expect(event.sourceAsset).to.equal(susd);
    expect(event.sourceAmount).to.equal(sourceAmount);
    expect(event.destinationAsset).to.equal(seth);
  });

  it("should be able to swap tokens on Uniswap v3 - multi swap", async () => {
    let exchangeEvent = new Promise((resolve, reject) => {
      uniswapV3SwapGuard.on(
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

    const sourceAmount = (100e18).toString();
    const IUniswapV3Router = await hre.artifacts.readArtifact("IUniswapV3Router");
    const iUniswapV3Router = new ethers.utils.Interface(IUniswapV3Router.abi);
    // https://etherscan.io/tx/0xa8423934015c7e893e06721bbc01e42b8139b20764b9d23dbcb831e7b18b0e60
    // path on etherscan 0x c4a11aaf6ea915ed7ac194161d2fc9384f15bff2 000bb8 c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2 0001f4 dac17f958d2ee523a2206206994597c13d831ec7
    // path we have      0x 0165878A594ca255338adfa4d48449f69242Eb8F 000bb8 610178dA211FEF7D417bC0e6FeD39F05609AD788 000bb8 2279B7A0a67DB372996a5FaB50D91eAA73d2eBe6
    const path =
      "0x" +
      susd.substring(2) + // source asset
      "000bb8" + // fee
      slink.substring(2) + // path asset
      "000bb8" + // fee
      seth.substring(2); // destination asset
    const exactInputParams = {
      path: path,
      recipient: poolManagerLogicProxy.address,
      deadline: 1,
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
      slink.substring(2) + // unsupported asset
      "000bb8" +
      susd.substring(2) +
      "000bb8" +
      seth.substring(2);
    swapABI = iUniswapV3Router.encodeFunctionData("exactInput", [badExactInputParams]);
    await expect(poolLogicProxy.connect(manager).execTransaction(uniswapV3Router.address, swapABI)).to.be.revertedWith(
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
    badExactInputParams.path = "0x" + susd.substring(2) + "000bb8" + seth.substring(2) + "000bb8" + slink.substring(2); // unsupported asset
    swapABI = iUniswapV3Router.encodeFunctionData("exactInput", [badExactInputParams]);
    await expect(poolLogicProxy.connect(manager).execTransaction(uniswapV3Router.address, swapABI)).to.be.revertedWith(
      "unsupported destination asset",
    );
    badExactInputParams.path = path;

    // fail to swap direct asset to asset because recipient is not the pool address
    badExactInputParams.recipient = user1.address;
    swapABI = iUniswapV3Router.encodeFunctionData("exactInput", [exactInputParams]);
    await expect(poolLogicProxy.connect(manager).execTransaction(uniswapV3Router.address, swapABI)).to.be.revertedWith(
      "recipient is not pool",
    );

    exactInputParams.recipient = poolLogicProxy.address;
    // succeed swapping direct asset to asset
    await uniswapV3Router.givenCalldataReturn(swapABI, []);
    swapABI = iUniswapV3Router.encodeFunctionData("exactInput", [exactInputParams]);
    await poolLogicProxy.connect(manager).execTransaction(uniswapV3Router.address, swapABI);

    let event = await exchangeEvent;
    expect(event.sourceAsset).to.equal(susd);
    expect(event.sourceAmount).to.equal(sourceAmount);
    expect(event.destinationAsset).to.equal(seth);
  });

  it("should be able to mint manager fee", async () => {
    await poolFactory.setDaoFee(10, 100);
    const daoFees = await poolFactory.getDaoFee();
    expect(daoFees[0]).to.be.equal(10);
    expect(daoFees[1]).to.be.equal(100);

    await poolFactory.transferOwnership(dao.address);
    expect(await poolFactory.owner()).to.be.equal(dao.address);

    await assetHandler.setChainlinkTimeout(9000000);

    let availableFee = await poolLogicProxy.availableManagerFee();
    let tokenPricePreMint = await poolLogicProxy.tokenPrice();
    let totalSupplyPreMint = await poolLogicProxy.totalSupply();

    await poolLogicProxy.mintManagerFee();

    let tokenPricePostMint = await poolLogicProxy.tokenPrice();
    let totalSupplyPostMint = await poolLogicProxy.totalSupply();

    checkAlmostSame(totalSupplyPostMint, totalSupplyPreMint.add(availableFee));
    checkAlmostSame(tokenPricePostMint, tokenPricePreMint.mul(totalSupplyPreMint).div(totalSupplyPostMint));

    checkAlmostSame(await poolLogicProxy.balanceOf(dao.address), availableFee.mul(daoFees[0]).div(daoFees[1]));

    await assetHandler.setChainlinkTimeout(90000);
  });

  it("should be able to pause deposit, exchange/execute and withdraw", async function () {
    let poolLogicManagerProxy = poolLogicProxy.connect(manager);

    await expect(poolFactory.pause()).to.be.revertedWith("caller is not the owner");
    await poolFactory.connect(dao).pause();
    expect(await poolFactory.isPaused()).to.be.true;

    await expect(poolLogicProxy.deposit(susd, (100e18).toString())).to.be.revertedWith("contracts paused");
    await expect(poolLogicProxy.withdraw((100e18).toString())).to.be.revertedWith("contracts paused");
    await expect(poolLogicManagerProxy.execTransaction(synthetix.address, "0x00")).to.be.revertedWith(
      "contracts paused",
    );

    await expect(poolFactory.unpause()).to.be.revertedWith("caller is not the owner");
    await poolFactory.connect(dao).unpause();
    expect(await poolFactory.isPaused()).to.be.false;

    await expect(poolLogicProxy.deposit(susd, (100e18).toString())).to.not.be.revertedWith("contracts paused");
    await expect(poolLogicProxy.withdraw((100e18).toString())).to.not.be.revertedWith("contracts paused");
    await expect(poolLogicManagerProxy.execTransaction(synthetix.address, "0x00")).to.not.be.revertedWith(
      "contracts paused",
    );
  });

  describe("AssetHandler", function () {
    it("only owner should be able to remove assets", async function () {
      expect(await assetHandler.assetTypes(susd)).to.be.equal(0);
      expect(await assetHandler.assetTypes(seth)).to.be.equal(0);
      expect(await assetHandler.assetTypes(slink)).to.be.equal(0);
      expect(await assetHandler.assetTypes(ZERO_ADDRESS)).to.be.equal(0);
      expect(await assetHandler.priceAggregators(susd)).to.be.equal(usd_price_feed.address);
      expect(await assetHandler.priceAggregators(seth)).to.be.equal(eth_price_feed.address);
      expect(await assetHandler.priceAggregators(slink)).to.be.equal(link_price_feed.address);
      expect(await assetHandler.priceAggregators(ZERO_ADDRESS)).to.be.equal(ZERO_ADDRESS);
      expect(await assetHandler.getAssetTypeAndAggregator(susd)).to.deep.equal([0, usd_price_feed.address]);

      await expect(assetHandler.connect(manager).removeAsset(slink)).to.be.revertedWith(
        "Ownable: caller is not the owner",
      );

      await assetHandler.removeAsset(susd);
      await assetHandler.removeAsset(seth);
      await assetHandler.removeAsset(slink);
      expect(await assetHandler.assetTypes(susd)).to.be.equal(0);
      expect(await assetHandler.assetTypes(seth)).to.be.equal(0);
      expect(await assetHandler.assetTypes(slink)).to.be.equal(0);
      expect(await assetHandler.priceAggregators(susd)).to.be.equal(ZERO_ADDRESS);
      expect(await assetHandler.priceAggregators(seth)).to.be.equal(ZERO_ADDRESS);
      expect(await assetHandler.priceAggregators(slink)).to.be.equal(ZERO_ADDRESS);
    });

    it("only owner should be able to add asset/assets", async function () {
      await expect(assetHandler.connect(manager).addAsset(slink, 0, link_price_feed.address)).to.be.revertedWith(
        "Ownable: caller is not the owner",
      );
      await expect(
        assetHandler.connect(manager).addAssets([{ asset: slink, assetType: 0, aggregator: link_price_feed.address }]),
      ).to.be.revertedWith("Ownable: caller is not the owner");

      await assetHandler.addAsset(slink, 0, link_price_feed.address);
      await assetHandler.addAssets([
        { asset: susd, assetType: 0, aggregator: usd_price_feed.address },
        { asset: seth, assetType: 0, aggregator: eth_price_feed.address },
      ]);

      expect(await assetHandler.assetTypes(susd)).to.be.equal(0);
      expect(await assetHandler.assetTypes(seth)).to.be.equal(0);
      expect(await assetHandler.assetTypes(slink)).to.be.equal(0);
      expect(await assetHandler.assetTypes(ZERO_ADDRESS)).to.be.equal(0);
      expect(await assetHandler.priceAggregators(susd)).to.be.equal(usd_price_feed.address);
      expect(await assetHandler.priceAggregators(seth)).to.be.equal(eth_price_feed.address);
      expect(await assetHandler.priceAggregators(slink)).to.be.equal(link_price_feed.address);
      expect(await assetHandler.priceAggregators(ZERO_ADDRESS)).to.be.equal(ZERO_ADDRESS);
    });

    it("only owner should be able to set chainlink timeout", async function () {
      expect(await assetHandler.chainlinkTimeout()).to.be.equal(90000);

      await expect(assetHandler.connect(manager).setChainlinkTimeout(90)).to.be.revertedWith(
        "Ownable: caller is not the owner",
      );

      await assetHandler.setChainlinkTimeout(90);

      expect(await assetHandler.chainlinkTimeout()).to.be.equal(90);
    });

    it("should be able to get usd price", async function () {
      // refresh timestamp of Chainlink price round data
      await updateChainlinkAggregators(usd_price_feed, eth_price_feed, link_price_feed);

      await expect(assetHandler.getUSDPrice(ZERO_ADDRESS)).to.be.revertedWith("Price aggregator not found");

      // try with again with no aggregator
      await expect(assetHandler.addAsset(badtoken, 1, ZERO_ADDRESS)).to.be.revertedWith(
        "aggregator address cannot be 0",
      );
      await expect(assetHandler.getUSDPrice(badtoken)).to.be.revertedWith("Price aggregator not found");
      await assetHandler.removeAsset(badtoken);

      // price get failed
      const AggregatorV3 = await hre.artifacts.readArtifact("AggregatorV3Interface");
      const iAggregatorV3 = new ethers.utils.Interface(AggregatorV3.abi);
      const latestRoundDataABI = iAggregatorV3.encodeFunctionData("latestRoundData", []);
      await usd_price_feed.givenCalldataRevert(latestRoundDataABI);
      await expect(assetHandler.getUSDPrice(susd)).to.be.revertedWith("Price get failed");

      // chainlink timeout
      const current = (await ethers.provider.getBlock()).timestamp;
      await usd_price_feed.givenCalldataReturn(
        latestRoundDataABI,
        ethers.utils.solidityPack(
          ["uint256", "int256", "uint256", "uint256", "uint256"],
          [0, 100000000, 0, current, 0],
        ),
      );

      await assetHandler.setChainlinkTimeout(0);
      await expect(assetHandler.getUSDPrice(susd)).to.be.revertedWith("Chainlink price expired");

      await assetHandler.setChainlinkTimeout(3600 * 25);
      expect(await assetHandler.getUSDPrice(susd)).to.be.equal((1e18).toString());

      await usd_price_feed.givenCalldataReturn(
        latestRoundDataABI,
        ethers.utils.solidityPack(["uint256", "int256", "uint256", "uint256", "uint256"], [0, 0, 0, current, 0]),
      );
      await expect(assetHandler.getUSDPrice(susd)).to.be.revertedWith("Price not available");
    });
  });

  describe("Members", () => {
    it("should be able to manage members", async () => {
      expect(await poolManagerLogicProxy.numberOfMembers()).to.be.equal(0);

      await poolManagerLogicProxy.connect(manager).addMember(user1.address);

      expect(await poolManagerLogicProxy.numberOfMembers()).to.be.equal(1);
      expect(await poolManagerLogicProxy.isMemberAllowed(user1.address)).to.be.true;

      await poolManagerLogicProxy.connect(manager).removeMember(user1.address);

      expect(await poolManagerLogicProxy.isMemberAllowed(user1.address)).to.be.false;
      expect(await poolManagerLogicProxy.numberOfMembers()).to.be.equal(0);
    });

    it("Adding members works correctly", async () => {
      expect(await poolManagerLogicProxy.numberOfMembers()).to.be.equal(0);

      await poolManagerLogicProxy.connect(manager).addMember(user1.address);

      expect(await poolManagerLogicProxy.isMemberAllowed(user1.address)).to.be.true;

      await poolManagerLogicProxy.connect(manager).addMembers([user1.address, user2.address, user3.address]);

      expect(await poolManagerLogicProxy.numberOfMembers()).to.be.equal(3);
      expect(await poolManagerLogicProxy.isMemberAllowed(user1.address)).to.be.true;
      expect(await poolManagerLogicProxy.isMemberAllowed(user2.address)).to.be.true;
      expect(await poolManagerLogicProxy.isMemberAllowed(user3.address)).to.be.true;
    });

    it("Removing members works correctly", async () => {
      expect(await poolManagerLogicProxy.numberOfMembers()).to.be.equal(3);

      await poolManagerLogicProxy.connect(manager).removeMembers([user1.address, user2.address, user3.address]);

      expect(await poolManagerLogicProxy.numberOfMembers()).to.be.equal(0);
    });
  });

  it("can set Sushi pool ID", async () => {
    expect(sushiLPAssetGuard.setSushiPoolId(ZERO_ADDRESS, "1")).to.be.revertedWith("Invalid lpToken address");

    const contract = "0x1111111111111111111111111111111111111111";
    await sushiLPAssetGuard.setSushiPoolId(contract, "1");
    const poolId = await sushiLPAssetGuard.sushiPoolIds(contract);
    expect(poolId).to.be.equal("1");
  });

  it("should be able to upgrade/set implementation logic", async function () {
    await expect(poolFactory.setLogic(TESTNET_DAO, TESTNET_DAO)).to.be.revertedWith("caller is not the owner");
    await poolFactory.connect(dao).setLogic(TESTNET_DAO, TESTNET_DAO);

    let poolManagerLogicAddress = await poolFactory.getLogic(1);
    expect(poolManagerLogicAddress).to.equal(TESTNET_DAO);

    let poolLogicAddress = await poolFactory.getLogic(2);
    expect(poolLogicAddress).to.equal(TESTNET_DAO);

    await poolFactory.connect(dao).setLogic(poolLogic.address, poolManagerLogic.address);
  });
});
