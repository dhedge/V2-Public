// import { updateChainlinkAggregators } from "./TestHelpers";

// Place holder addresses
const KOVAN_ADDRESS_RESOLVER = "0x242a3DF52c375bEe81b1c668741D7c63aF68FDD2";
const TESTNET_DAO = "0xab0c25f17e993F90CaAaec06514A2cc28DEC340b";

const { link } = require("@ethereum-waffle/compiler");
const { expect } = require("chai");
const abiCoder = ethers.utils.defaultAbiCoder;

const { updateChainlinkAggregators, currentBlockTimestamp } = require("./TestHelpers");

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
let synthetixGuard, uniswapV2Guard, uniswapV3SwapGuard; // contract guards
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

// from mainnet
// const susd =
//     '0x57ab1ec28d129707052df4df418d58a2d46d5f51'
// const seth =
//     '0x5e74c9036fb86bd7ecdcb084a0673efc32ea31cb'
// const slink =
//     '0xbbc455cb4f1b9e4bfc4b73970d360c8f032efee6'

describe("PoolFactory", function () {
  before(async function () {
    [logicOwner, manager, dao, user1] = await ethers.getSigners();

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

    // mock ISushiMiniChefV2
    IMiniChefV2 = await hre.artifacts.readArtifact("IMiniChefV2");
    iMiniChefV2 = new ethers.utils.Interface(IMiniChefV2.abi);

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

    IERC20 = await hre.artifacts.readArtifact("ERC20UpgradeSafe");
    iERC20 = new ethers.utils.Interface(IERC20.abi);
    let decimalsABI = iERC20.encodeFunctionData("decimals", []);
    await susdProxy.givenCalldataReturnUint(decimalsABI, "18");
    await sethProxy.givenCalldataReturnUint(decimalsABI, "18");
    await slinkProxy.givenCalldataReturnUint(decimalsABI, "18");

    // Aggregators
    await updateChainlinkAggregators(usd_price_feed, eth_price_feed, link_price_feed);

    AssetHandlerLogic = await ethers.getContractFactory("AssetHandler");
    assetHandlerLogic = await AssetHandlerLogic.deploy();

    // Deploy Sushi LP Aggregator
    const SushiLPAggregator = await ethers.getContractFactory("SushiLPAggregator");
    sushiLPAggregator = await SushiLPAggregator.deploy(
      sushiLPLinkWeth,
      link_price_feed.address,
      eth_price_feed.address,
    );

    PoolLogic = await ethers.getContractFactory("PoolLogic");
    poolLogic = await PoolLogic.deploy();

    PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
    poolManagerLogic = await PoolManagerLogic.deploy();

    const PoolFactoryLogic = await ethers.getContractFactory("PoolFactory");
    poolFactoryLogic = await PoolFactoryLogic.deploy();

    // Deploy ProxyAdmin
    const ProxyAdmin = await ethers.getContractFactory("ProxyAdmin");
    const proxyAdmin = await ProxyAdmin.deploy();
    await proxyAdmin.deployed();

    // Deploy AssetHandlerProxy
    const AssetHandlerProxy = await ethers.getContractFactory("OZProxy");
    const assetHandlerProxy = await AssetHandlerProxy.deploy(assetHandlerLogic.address, manager.address, "0x");
    await assetHandlerProxy.deployed();

    assetHandler = await AssetHandlerLogic.attach(assetHandlerProxy.address);

    // Deploy PoolFactoryProxy
    const PoolFactoryProxy = await ethers.getContractFactory("OZProxy");
    const poolFactoryProxy = await PoolFactoryProxy.deploy(poolFactoryLogic.address, manager.address, "0x");
    await poolFactoryProxy.deployed();

    poolFactory = await PoolFactoryLogic.attach(poolFactoryProxy.address);

    // Initialize Asset Price Consumer
    const assetSusd = { asset: susd, assetType: 0, aggregator: usd_price_feed.address };
    const assetSeth = { asset: seth, assetType: 0, aggregator: eth_price_feed.address };
    const assetSlink = { asset: slink, assetType: 0, aggregator: link_price_feed.address };
    const assetSushiLPLinkWeth = { asset: sushiLPLinkWeth, assetType: 2, aggregator: sushiLPAggregator.address };
    const assetHandlerInitAssets = [assetSusd, assetSeth, assetSlink, assetSushiLPLinkWeth];

    await assetHandler.initialize(poolFactoryProxy.address, assetHandlerInitAssets);
    await assetHandler.deployed();

    // Initialise pool factory
    await poolFactory.initialize(poolLogic.address, poolManagerLogic.address, assetHandlerProxy.address, dao.address);
    await poolFactory.deployed();

    // Deploy contract guards
    const SynthetixGuard = await ethers.getContractFactory("SynthetixGuard");
    synthetixGuard = await SynthetixGuard.deploy(addressResolver.address);
    synthetixGuard.deployed();

    const UniswapV2Guard = await ethers.getContractFactory("UniswapV2Guard");
    uniswapV2Guard = await UniswapV2Guard.deploy();
    uniswapV2Guard.deployed();

    const UniswapV3SwapGuard = await ethers.getContractFactory("UniswapV3SwapGuard");
    uniswapV3SwapGuard = await UniswapV3SwapGuard.deploy();
    uniswapV3SwapGuard.deployed();

    // Deploy asset guards
    const ERC20Guard = await ethers.getContractFactory("ERC20Guard");
    erc20Guard = await ERC20Guard.deploy();
    erc20Guard.deployed();

    const SushiLPAssetGuard = await ethers.getContractFactory("SushiLPAssetGuard");
    sushiLPAssetGuard = await SushiLPAssetGuard.deploy(sushiMiniChefV2.address, [
      [sushiLPLinkWeth, sushiLPLinkWethPoolId],
    ]); // initialise with Sushi staking pool Id
    sushiLPAssetGuard.deployed();

    await poolFactory.connect(dao).setAssetGuard(0, erc20Guard.address);
    await poolFactory.connect(dao).setAssetGuard(2, sushiLPAssetGuard.address);
    await poolFactory.connect(dao).setContractGuard(synthetix.address, synthetixGuard.address);
    await poolFactory.connect(dao).setContractGuard(uniswapV2Router.address, uniswapV2Guard.address);
    await poolFactory.connect(dao).setContractGuard(uniswapV3Router.address, uniswapV3SwapGuard.address);
  });

  it("Should be able to createFund", async function () {
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

    // await poolManagerLogic.initialize(poolFactory.address, manager.address, "Barren Wuffet", mock.address, [sethKey])

    // console.log("Passed poolManagerLogic Init!")

    // await poolLogic.initialize(poolFactory.address, false, manager.address, "Barren Wuffet", "Test Fund", "DHTF", mock.address)

    // console.log("Passed poolLogic Init!")

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

    let deployedFundsLength = await poolFactory.deployedFundsLength();
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

    // check create fund works correctly for AssetAdded event (fundAddress = poolLogic)
    expect(poolManagerLogicProxy.filters.AssetAdded(poolLogicProxy.address).topics[1]).to.be.equal(
      ethers.utils.hexZeroPad(poolLogicProxy.address, 32).toLowerCase(),
    );

    //default assets are supported
    expect(await poolManagerLogicProxy.numberOfSupportedAssets()).to.equal("2");
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
      logicOwner.address,
      poolLogicProxy.address,
      (100e18).toString(),
    ]);
    await susdProxy.givenCalldataReturnBool(transferFromABI, true);

    let totalFundValue = await poolLogicProxy.totalFundValue();
    // As default there's susd and seth and each return 1 by IExchangeRates
    expect(totalFundValue.toString()).to.equal("0");

    await expect(poolLogicProxy.deposit(slink, (100e18).toString())).to.be.revertedWith("invalid deposit asset");
    await poolLogicProxy.deposit(susd, (100e18).toString());
    let event = await depositEvent;

    expect(event.fundAddress).to.equal(poolLogicProxy.address);
    expect(event.investor).to.equal(logicOwner.address);
    expect(event.assetDeposited).to.equal(susd);
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
            time: time,
          });
        },
      );

      setTimeout(() => {
        reject(new Error("timeout"));
      }, 60000);
    });

    // mock IERC20 balance
    let balanceOfABI = iERC20.encodeFunctionData("balanceOf", [poolLogicProxy.address]);
    await susdProxy.givenCalldataReturnUint(balanceOfABI, (100e18).toString());

    // Withdraw 50%
    let withdrawAmount = 50e18;
    let totalSupply = await poolLogicProxy.totalSupply();
    let totalFundValue = await poolLogicProxy.totalFundValue();

    await expect(poolLogicProxy.withdraw(withdrawAmount.toString())).to.be.revertedWith("cooldown active");

    // await poolFactory.setExitCooldown(0);
    ethers.provider.send("evm_increaseTime", [3600 * 24]); // add 1 day

    await poolLogicProxy.withdraw(withdrawAmount.toString());

    // let [exitFeeNumerator, exitFeeDenominator] = await poolFactory.getExitFee()
    // let daoExitFee = withdrawAmount * exitFeeNumerator / exitFeeDenominator

    let event = await withdrawalEvent;

    let fundTokensWithdrawn = withdrawAmount;
    let valueWithdrawn = (fundTokensWithdrawn / totalSupply) * totalFundValue;
    expect(event.fundAddress).to.equal(poolLogicProxy.address);
    expect(event.investor).to.equal(logicOwner.address);
    expect(event.valueWithdrawn).to.equal(valueWithdrawn.toString());
    expect(event.fundTokensWithdrawn).to.equal(fundTokensWithdrawn.toString());
    expect(event.totalInvestorFundTokens).to.equal((50e18).toString());
    expect(event.fundValue).to.equal((100e18).toString());
    expect(event.totalSupply).to.equal((100e18 - fundTokensWithdrawn).toString());
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

    let deployedFundsLength = await poolFactory.deployedFundsLength();
    let fundAddress = await poolFactory.deployedFunds(deployedFundsLength - 1);
    let poolLogicPrivateProxy = await PoolLogic.attach(fundAddress);
    let poolManagerLogicPrivateProxy = await PoolManagerLogic.attach(await poolLogicPrivateProxy.poolManagerLogic());

    let transferFromABI = iERC20.encodeFunctionData("transferFrom", [
      logicOwner.address,
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

    let numberOfSupportedAssets = await poolManagerLogicManagerProxy.numberOfSupportedAssets();
    expect(numberOfSupportedAssets).to.eq("3");

    // Can not remove persist asset
    await expect(poolManagerLogicUser1Proxy.changeAssets([], [[slink, false]])).to.be.revertedWith(
      "only manager or trader",
    );

    // Can't add invalid asset
    let invalid_synth_asset = "0x823bE81bbF96BEc0e25CA13170F5AaCb5B79ba83";
    await expect(poolManagerLogicManagerProxy.changeAssets([[invalid_synth_asset, false]], [])).to.be.revertedWith(
      "invalid asset",
    );

    // Can't remove asset with non zero balance
    // mock IERC20 balanceOf to return non zero
    let balanceOfABI = iERC20.encodeFunctionData("balanceOf", [poolLogicProxy.address]);
    await slinkProxy.givenCalldataReturnUint(balanceOfABI, 1);

    await expect(poolManagerLogicManagerProxy.changeAssets([], [[slink, false]])).to.be.revertedWith(
      "revert cannot remove non-empty asset",
    );

    // Can remove asset
    await slinkProxy.givenCalldataReturnUint(balanceOfABI, 0);
    await poolManagerLogicManagerProxy.changeAssets([], [[slink, false]]);

    numberOfSupportedAssets = await poolManagerLogicManagerProxy.numberOfSupportedAssets();
    expect(numberOfSupportedAssets).to.eq("2");

    expect(await poolManagerLogicProxy.isDepositAsset(slink)).to.be.false;
    expect(await poolManagerLogicProxy.numberOfDepositAssets()).to.be.equal(2);
    await poolManagerLogicManagerProxy.changeAssets([[slink, true]], []);
    expect(await poolManagerLogicProxy.isDepositAsset(slink)).to.be.true;
    expect(await poolManagerLogicProxy.numberOfDepositAssets()).to.be.equal(3);
    await poolManagerLogicManagerProxy.changeAssets([], [[slink, true]]);
    expect(await poolManagerLogicProxy.isDepositAsset(slink)).to.be.false;
    expect(await poolManagerLogicProxy.numberOfDepositAssets()).to.be.equal(2);
    await poolManagerLogicManagerProxy.changeAssets([], [[slink, false]]);
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
    const daoAddress = await poolFactory.getDaoAddress();
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
      uniswapV2Guard.on("Exchange", (managerLogicAddress, sourceAsset, sourceAmount, destinationAsset, time, event) => {
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

    await expect(
      poolLogicProxy.connect(manager).execTransaction("0x0000000000000000000000000000000000000000", swapABI),
    ).to.be.revertedWith("non-zero address is required");

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
    await expect(
      poolLogicProxy.connect(manager).execTransaction("0x0000000000000000000000000000000000000000", swapABI),
    ).to.be.revertedWith("non-zero address is required");

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
    badExactInputSingleParams.recipient = poolManagerLogicProxy.address;

    // succeed swapping direct asset to asset
    await uniswapV3Router.givenCalldataReturn(swapABI, []);
    swapABI = iUniswapV3Router.encodeFunctionData("exactInputSingle", [exactInputSingleParams]);
    await poolLogicProxy.connect(manager).execTransaction(uniswapV3Router.address, swapABI);

    let event = await exchangeEvent;
    expect(event.sourceAsset).to.equal(susd);
    expect(event.sourceAmount).to.equal((100e18).toString());
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
    const path =
      "0x" +
      susd.substring(2) + // source asset
      "000bb8" + // fee
      slink.substring(2) + // path asset
      "000bb8" + // fee
      seth.substring(2) + // destination asset
      "000000000000000000000000000000000000000000000000000000000000";
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
    await expect(
      poolLogicProxy.connect(manager).execTransaction("0x0000000000000000000000000000000000000000", swapABI),
    ).to.be.revertedWith("non-zero address is required");

    // fail to swap direct asset to asset because unsupported source asset
    badExactInputParams.path =
      "0x" +
      slink.substring(2) + // unsupported asset
      "000bb8" +
      susd.substring(2) +
      "000bb8" +
      seth.substring(2) +
      "000000000000000000000000000000000000000000000000000000000000";
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
    badExactInputParams.recipient = poolManagerLogicProxy.address;

    // succeed swapping direct asset to asset
    await uniswapV3Router.givenCalldataReturn(swapABI, []);
    swapABI = iUniswapV3Router.encodeFunctionData("exactInput", [exactInputParams]);
    await poolLogicProxy.connect(manager).execTransaction(uniswapV3Router.address, swapABI);

    let event = await exchangeEvent;
    expect(event.sourceAsset).to.equal(susd);
    expect(event.sourceAmount).to.equal((100e18).toString());
    expect(event.destinationAsset).to.equal(seth);
  });

  it("should be able to pause deposit, exchange/execute and withdraw", async function () {
    let poolLogicManagerProxy = poolLogicProxy.connect(manager);

    await expect(poolFactory.pause()).to.be.revertedWith("only dao");
    await poolFactory.connect(dao).pause();
    expect(await poolFactory.isPaused()).to.be.true;

    await expect(poolLogicProxy.deposit(susd, (100e18).toString())).to.be.revertedWith("contracts paused");
    await expect(poolLogicProxy.withdraw((100e18).toString())).to.be.revertedWith("contracts paused");
    await expect(poolLogicManagerProxy.execTransaction(synthetix.address, "0x00")).to.be.revertedWith(
      "contracts paused",
    );

    await expect(poolFactory.unpause()).to.be.revertedWith("only dao");
    await poolFactory.connect(dao).unpause();
    expect(await poolFactory.isPaused()).to.be.false;

    await expect(poolLogicProxy.deposit(susd, (100e18).toString())).to.not.be.revertedWith("contracts paused");
    await expect(poolLogicProxy.withdraw((100e18).toString())).to.not.be.revertedWith("contracts paused");
    await expect(poolLogicManagerProxy.execTransaction(synthetix.address, "0x00")).to.not.be.revertedWith(
      "contracts paused",
    );
  });

  it("can withdraw staked Sushi LP token", async function () {
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
            time: time,
          });
        },
      );

      setTimeout(() => {
        reject(new Error("timeout"));
      }, 60000);
    });

    const withdrawStakedEvent = new Promise((resolve, reject) => {
      sushiLPAssetGuard.on("WithdrawStaked", (fundAddress, asset, to, withdrawAmount, time, event) => {
        event.removeListener();

        resolve({
          fundAddress,
          asset,
          to,
          withdrawAmount,
          time,
        });
      });

      setTimeout(() => {
        reject(new Error("timeout"));
      }, 60000);
    });

    // refresh timestamp of Chainlink price round data
    await updateChainlinkAggregators(usd_price_feed, eth_price_feed, link_price_feed);

    // enable Sushi LP token to pool
    await poolManagerLogicProxy.connect(manager).changeAssets([[sushiLPLinkWeth, false]], []);

    // mock 20 sUSD in pool
    let balanceOfABI = iERC20.encodeFunctionData("balanceOf", [poolLogicProxy.address]);
    await susdProxy.givenCalldataReturnUint(balanceOfABI, (20e18).toString());

    // mock 100 Sushi LP staked in MiniChefV2
    const iMiniChefV2 = new ethers.utils.Interface(IMiniChefV2.abi);
    let userInfo = iMiniChefV2.encodeFunctionData("userInfo", [sushiLPLinkWethPoolId, poolLogicProxy.address]);
    const amountLPStaked = (100e18).toString();
    const amountRewarded = (0).toString();
    await sushiMiniChefV2.givenCalldataReturn(
      userInfo,
      abiCoder.encode(["uint256", "uint256"], [amountLPStaked, amountRewarded]),
    );

    console.log("get sushiLPPrice");
    const sushiLPPrice = await sushiLPAggregator.latestRoundData();
    console.log("sushiLPPrice:", sushiLPPrice[1].toString());

    const totalSupply = await poolLogicProxy.totalSupply();
    console.log("totalSupply:", totalSupply);
    const totalFundValue = await poolLogicProxy.totalFundValue();
    console.log("totalFundValue:", totalFundValue);

    // Withdraw 10 tokens
    const withdrawAmount = 10e18;
    const investorFundBalance = await poolLogicProxy.balanceOf(logicOwner.address);

    ethers.provider.send("evm_increaseTime", [3600 * 24]); // add 1 day to avoid cooldown revert
    await poolLogicProxy.withdraw(withdrawAmount.toString());

    const eventWithdrawal = await withdrawalEvent;
    const eventWithdrawStaked = await withdrawStakedEvent;
    console.log("eventWithdrawStaked:", eventWithdrawStaked);

    const fundTokensWithdrawn = withdrawAmount;
    const valueWithdrawn = (fundTokensWithdrawn / totalSupply) * totalFundValue;

    expect(eventWithdrawal.fundAddress).to.equal(poolLogicProxy.address);
    expect(eventWithdrawal.investor).to.equal(logicOwner.address);
    expect(eventWithdrawal.valueWithdrawn).to.equal(valueWithdrawn.toString());
    expect(eventWithdrawal.fundTokensWithdrawn).to.equal(fundTokensWithdrawn.toString());
    expect(eventWithdrawal.totalInvestorFundTokens).to.equal((investorFundBalance - withdrawAmount).toString());
    expect(eventWithdrawal.fundValue).to.equal(totalFundValue.toString());
    expect(eventWithdrawal.totalSupply).to.equal((totalSupply - fundTokensWithdrawn).toString());
  });

  it("should be able to upgrade/set implementation logic", async function () {
    await poolFactory.setLogic(TESTNET_DAO, TESTNET_DAO);

    let poolManagerLogicAddress = await poolFactory.getLogic(1);
    expect(poolManagerLogicAddress).to.equal(TESTNET_DAO);

    let poolLogicAddress = await poolFactory.getLogic(2);
    expect(poolLogicAddress).to.equal(TESTNET_DAO);
  });
});
