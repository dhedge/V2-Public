const { ethers, upgrades } = require("hardhat");

// Place holder addresses
const KOVAN_ADDRESS_RESOLVER = "0x242a3DF52c375bEe81b1c668741D7c63aF68FDD2";
const TESTNET_DAO = "0xab0c25f17e993F90CaAaec06514A2cc28DEC340b";
const externalValidToken = "0xb79fad4ca981472442f53d16365fdf0305ffd8e9"; //random address
const externalInvalidToken = "0x7cea675598da73f859696b483c05a4f135b2092e"; //random address

const { expect } = require("chai");
const abiCoder = ethers.utils.defaultAbiCoder;

const { updateChainlinkAggregators, currentBlockTimestamp, checkAlmostSame, toBytes32 } = require("../TestHelpers");

let logicOwner, manager, dao, investor, user1, user2;
let poolFactory,
  PoolLogic,
  PoolManagerLogic,
  poolLogic,
  poolManagerLogic,
  poolLogicProxy,
  poolManagerLogicProxy,
  poolPerformanceProxy,
  fundAddress;

let IERC20, iERC20, IMiniChefV2, iMiniChefV2;
let synthetixGuard, uniswapV2RouterGuard, uniswapV3SwapGuard, sushiMiniChefV2Guard; // contract guards
let erc20Guard, sushiLPAssetGuard, openAssetGuard; // asset guards
let addressResolver, synthetix, uniswapV2Router, uniswapV3Router; // integrating contracts
let susd, seth, slink;
let oneInchRouter;
let susdAsset, susdProxy, sethAsset, sethProxy, slinkAsset, slinkProxy;
let sushiLPAggregator; // local aggregators
let usd_price_feed, eth_price_feed, link_price_feed; // integrating aggregators

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
const _SYNTHETIX_KEY = "0x53796e7468657469780000000000000000000000000000000000000000000000"; // Synthetix

const susdKey = "0x7355534400000000000000000000000000000000000000000000000000000000";
const sethKey = "0x7345544800000000000000000000000000000000000000000000000000000000";
const slinkKey = "0x734c494e4b000000000000000000000000000000000000000000000000000000";

const FIVE_TOKENS = "5000000000000000000";
const TEN_TOKENS = "10000000000000000000";
const TWENTY_TOKENS = "20000000000000000000";
const ONE_HUNDRED_TOKENS = "100000000000000000000";

const POOL_STORAGE_VERSION = "99999";

describe("PoolFactory", function () {
  beforeEach(async function () {
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
    oneInchRouter = await MockContract.deploy();
    susd = susdProxy.address;
    seth = sethProxy.address;
    slink = slinkProxy.address;
    sushiLPLinkWeth = sushiLPLinkWethAsset.address;
    sushiLPLinkWethPoolId = 0; // set Sushi LP staking contract Pool Id
    badtoken = "0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB";

    // mock IAddressResolver
    const IAddressResolver = await hre.artifacts.readArtifact(
      "contracts/interfaces/synthetix/IAddressResolver.sol:IAddressResolver",
    );
    const iAddressResolver = new ethers.utils.Interface(IAddressResolver.abi);
    let getAddressABI = iAddressResolver.encodeFunctionData("getAddress", [_SYNTHETIX_KEY]);
    await addressResolver.givenCalldataReturnAddress(getAddressABI, synthetix.address);

    const IUniswapV2Router = await hre.artifacts.readArtifact(
      "contracts/interfaces/uniswapv2/IUniswapV2Router.sol:IUniswapV2Router",
    );
    const iUniswapV2Router = new ethers.utils.Interface(IUniswapV2Router.abi);
    let factoryABI = iUniswapV2Router.encodeFunctionData("factory", []);
    await uniswapV2Router.givenCalldataReturnAddress(factoryABI, uniswapV2Factory.address);

    // mock Sushi LINK-WETH LP
    const IUniswapV2Pair = await hre.artifacts.readArtifact(
      "contracts/interfaces/uniswapv2/IUniswapV2Pair.sol:IUniswapV2Pair",
    );
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
    const ISynthetix = await hre.artifacts.readArtifact("contracts/interfaces/synthetix/ISynthetix.sol:ISynthetix");
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
    const ISynth = await hre.artifacts.readArtifact("contracts/interfaces/synthetix/ISynth.sol:ISynth");
    const iSynth = new ethers.utils.Interface(ISynth.abi);
    const proxyABI = iSynth.encodeFunctionData("proxy", []);
    await susdAsset.givenCalldataReturnAddress(proxyABI, susdProxy.address);
    await sethAsset.givenCalldataReturnAddress(proxyABI, sethProxy.address);
    await slinkAsset.givenCalldataReturnAddress(proxyABI, slinkProxy.address);

    // mock ISynthAddressProxy
    const ISynthAddressProxy = await hre.artifacts.readArtifact(
      "contracts/interfaces/synthetix/ISynthAddressProxy.sol:ISynthAddressProxy",
    );
    const iSynthAddressProxy = new ethers.utils.Interface(ISynthAddressProxy.abi);
    const targetABI = iSynthAddressProxy.encodeFunctionData("target", []);
    await susdProxy.givenCalldataReturnAddress(targetABI, susdAsset.address);
    await sethProxy.givenCalldataReturnAddress(targetABI, sethAsset.address);
    await slinkProxy.givenCalldataReturnAddress(targetABI, slinkAsset.address);

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

    const Governance = await ethers.getContractFactory("Governance");
    let governance = await Governance.deploy();
    console.log("governance deployed to:", governance.address);

    const PoolPerformance = await ethers.getContractFactory("PoolPerformance");
    const poolPerformance = await PoolPerformance.deploy();
    poolPerformanceProxy = await PoolPerformance.attach(poolPerformance.address);

    // PoolLogicV24 = await ethers.getContractFactory("PoolLogicV24");
    // poolLogicV24 = await PoolLogicV24.deploy();
    PoolLogic = await ethers.getContractFactory("PoolLogic");
    poolLogic = await PoolLogic.deploy();

    // PoolManagerLogicV24 = await ethers.getContractFactory("PoolManagerLogicV24");
    // poolManagerLogicV24 = await PoolManagerLogicV24.deploy();
    PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
    poolManagerLogic = await PoolManagerLogic.deploy();

    // Initialize Asset Price Consumer
    const assetSusd = { asset: susd, assetType: 0, aggregator: usd_price_feed.address };
    const assetSeth = { asset: seth, assetType: 0, aggregator: eth_price_feed.address };
    const assetSlink = { asset: slink, assetType: 0, aggregator: link_price_feed.address };
    const assetSushi = { asset: sushiToken.address, assetType: 0, aggregator: usd_price_feed.address }; // just peg price to USD
    const assetWmatic = { asset: wmaticToken.address, assetType: 0, aggregator: usd_price_feed.address }; // just peg price to USD
    const assetHandlerInitAssets = [assetSusd, assetSeth, assetSlink, assetSushi, assetWmatic];

    // await assetHandler.initialize(poolFactoryProxy.address, assetHandlerInitAssets);
    // await assetHandler.deployed();
    AssetHandlerLogic = await ethers.getContractFactory("contracts/assets/AssetHandler.sol:AssetHandler");
    assetHandler = await upgrades.deployProxy(AssetHandlerLogic, [assetHandlerInitAssets]);
    await assetHandler.deployed();
    console.log("assetHandler deployed to:", assetHandler.address);

    // const PoolFactoryLogicV24 = await ethers.getContractFactory("PoolFactoryV24");
    // poolFactoryV24 = await upgrades.deployProxy(PoolFactoryLogicV24, [
    //   poolLogicV24.address,
    //   poolManagerLogicV24.address,
    //   assetHandler.address,
    //   dao.address,
    //   governance.address,
    // ]);

    // await poolFactoryV24.deployed();
    // console.log("poolFactoryV24 deployed to:", poolFactoryV24.address);

    const PoolFactoryLogic = await ethers.getContractFactory("PoolFactory");
    poolFactory = await upgrades.deployProxy(PoolFactoryLogic, [
      poolLogic.address,
      poolManagerLogic.address,
      assetHandler.address,
      dao.address,
      governance.address,
    ]);
    console.log("poolFactory upgraded to: ", poolFactory.address);

    poolFactory.setPoolPerformanceAddress(poolPerformance.address);

    // Deploy Sushi LP Aggregator
    const UniV2LPAggregator = await ethers.getContractFactory("UniV2LPAggregator");
    sushiLPAggregator = await UniV2LPAggregator.deploy(sushiLPLinkWeth, poolFactory.address);
    const assetSushiLPLinkWeth = { asset: sushiLPLinkWeth, assetType: 2, aggregator: sushiLPAggregator.address };
    await assetHandler.addAssets([assetSushiLPLinkWeth]);

    // Deploy contract guards
    const SynthetixGuard = await ethers.getContractFactory("contracts/guards/SynthetixGuard.sol:SynthetixGuard");
    synthetixGuard = await SynthetixGuard.deploy(addressResolver.address);
    synthetixGuard.deployed();

    const UniswapV2RouterGuard = await ethers.getContractFactory(
      "contracts/guards/UniswapV2RouterGuard.sol:UniswapV2RouterGuard",
    );
    uniswapV2RouterGuard = await UniswapV2RouterGuard.deploy(2, 100); // set slippage 2%
    uniswapV2RouterGuard.deployed();

    const UniswapV3SwapGuard = await ethers.getContractFactory(
      "contracts/guards/uniswapV3/UniswapV3SwapGuard.sol:UniswapV3SwapGuard",
    );
    uniswapV3SwapGuard = await UniswapV3SwapGuard.deploy();
    uniswapV3SwapGuard.deployed();

    const SushiMiniChefV2Guard = await ethers.getContractFactory(
      "contracts/guards/SushiMiniChefV2Guard.sol:SushiMiniChefV2Guard",
    );
    sushiMiniChefV2Guard = await SushiMiniChefV2Guard.deploy(sushiToken.address, wmaticToken.address);
    sushiMiniChefV2Guard.deployed();

    const OneInchV3Guard = await ethers.getContractFactory("contracts/guards/OneInchV3Guard.sol:OneInchV3Guard");
    oneInchV3Guard = await OneInchV3Guard.deploy(2, 100); // set slippage 2%
    oneInchV3Guard.deployed();

    // Deploy asset guards
    const ERC20Guard = await ethers.getContractFactory("contracts/guards/assetGuards/ERC20Guard.sol:ERC20Guard");
    erc20Guard = await ERC20Guard.deploy();
    erc20Guard.deployed();

    const SushiLPAssetGuard = await ethers.getContractFactory(
      "contracts/guards/assetGuards/SushiLPAssetGuard.sol:SushiLPAssetGuard",
    );
    sushiLPAssetGuard = await SushiLPAssetGuard.deploy(sushiMiniChefV2.address); // initialise with Sushi staking pool Id
    sushiLPAssetGuard.deployed();

    const OpenAssetGuard = await ethers.getContractFactory(
      "contracts/guards/assetGuards/OpenAssetGuard.sol:OpenAssetGuard",
    );
    openAssetGuard = await OpenAssetGuard.deploy([externalValidToken]); // initialise with random external token
    openAssetGuard.deployed();

    await governance.setAssetGuard(0, erc20Guard.address);
    await governance.setAssetGuard(2, sushiLPAssetGuard.address);
    await governance.setContractGuard(synthetix.address, synthetixGuard.address);
    await governance.setContractGuard(uniswapV2Router.address, uniswapV2RouterGuard.address);
    await governance.setContractGuard(uniswapV3Router.address, uniswapV3SwapGuard.address);
    await governance.setContractGuard(oneInchRouter.address, oneInchV3Guard.address);
    await governance.setContractGuard(sushiMiniChefV2.address, sushiMiniChefV2Guard.address);
    await governance.setAddresses([[toBytes32("openAssetGuard"), openAssetGuard.address]]);

    const openAssetGuardSetting = await poolFactory.getAddress(toBytes32("openAssetGuard"));
    console.log("openAssetGuardSetting:", openAssetGuardSetting);

    await updateChainlinkAggregators(usd_price_feed, eth_price_feed, link_price_feed);

    console.log("Creating Fund...");

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
  });

  // manager starts pool with $1
  // then direct deposits $1
  // directDepositFactor = $1
  // from here,
  // scenario 1:
  // pool goes down 50% in value (performance drop)
  // now token price returns 0?
  // No token price returns $1 and tokenPriceAdjustedForPerformance returns $0.5
  it("Ermin scenario 1", async function () {
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
    const funds = await poolFactory.getDeployedFunds();
    expect(funds[0]).not.to.be.undefined;
    poolLogicProxy = await PoolLogic.attach(funds[0]);
    let transferFromABI = iERC20.encodeFunctionData("transferFrom", [
      investor.address,
      poolLogicProxy.address,
      (100e18).toString(),
    ]);
    await susdProxy.givenMethodReturnBool(transferFromABI, true);

    await poolLogicProxy.deposit(susd, (100e18).toString());

    const oneDollar = 1e18;
    let balanceOfABI = iERC20.encodeFunctionData("balanceOf", [poolLogicProxy.address]);
    await susdProxy.givenCalldataReturnUint(balanceOfABI, (100e18).toString());

    expect((await poolPerformanceProxy.tokenPrice(poolLogicProxy.address)).toString()).to.equal(oneDollar.toString());
    expect((await poolPerformanceProxy.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
      oneDollar.toString(),
    );

    expect((await poolPerformanceProxy.tokenPriceAdjustedForManagerFee(poolLogicProxy.address)).toString()).to.equal(
      oneDollar.toString(),
    );
    expect(
      (await poolPerformanceProxy.tokenPriceAdjustedForPerformanceAndManagerFee(poolLogicProxy.address)).toString(),
    ).to.equal(oneDollar.toString());

    const twoDollar = 2e18;
    await susdProxy.givenCalldataReturnUint(balanceOfABI, (200e18).toString());

    expect((await poolPerformanceProxy.tokenPrice(poolLogicProxy.address)).toString()).to.equal(twoDollar.toString());
    expect((await poolPerformanceProxy.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
      oneDollar.toString(),
    );

    const oneDollarSixty = 16e17;
    expect((await poolPerformanceProxy.tokenPriceAdjustedForManagerFee(poolLogicProxy.address)).toString()).to.equal(
      oneDollarSixty.toString(),
    );
    expect(
      (await poolPerformanceProxy.tokenPriceAdjustedForPerformanceAndManagerFee(poolLogicProxy.address)).toString(),
    ).to.equal((oneDollarSixty - oneDollar).toString());

    const current = (await ethers.provider.getBlock()).timestamp;
    const AggregatorV3 = await hre.artifacts.readArtifact("AggregatorV3Interface");
    const iAggregatorV3 = new ethers.utils.Interface(AggregatorV3.abi);
    const latestRoundDataABI = iAggregatorV3.encodeFunctionData("latestRoundData", []);

    // Halve the usd price
    await usd_price_feed.givenCalldataReturn(
      latestRoundDataABI,
      ethers.utils.solidityPack(["uint256", "int256", "uint256", "uint256", "uint256"], [0, 50000000, 0, current, 0]),
    ); // $.5

    expect((await poolPerformanceProxy.tokenPrice(poolLogicProxy.address)).toString()).to.equal(oneDollar.toString());
    expect((await poolPerformanceProxy.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
      (oneDollar / 2).toString(),
    );
    // There is no manager fee because there is no performance because usdc price fell to $.50
    expect((await poolPerformanceProxy.tokenPriceAdjustedForManagerFee(poolLogicProxy.address)).toString()).to.equal(
      await poolPerformanceProxy.tokenPrice(poolLogicProxy.address),
    );
    expect(
      (await poolPerformanceProxy.tokenPriceAdjustedForPerformanceAndManagerFee(poolLogicProxy.address)).toString(),
    ).to.equal(await poolPerformanceProxy.tokenPriceAdjustedForPerformance(poolLogicProxy.address));
  });

  // manager starts pool with $1
  // then direct deposits $1
  // directDepositFactor = $1
  // from here,
  // scenario 2:
  // pool goes up 100% in value (performance gain)
  // now token price returns 3? (ie 200% gain)
  // No token price returns $4 (double the underlying value) and tokenPriceAdjustedForPerformance returns $2 (double the deposited value)
  it("Ermin scenario 2", async function () {
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
    const funds = await poolFactory.getDeployedFunds();
    expect(funds[0]).not.to.be.undefined;
    poolLogicProxy = await PoolLogic.attach(funds[0]);
    let transferFromABI = iERC20.encodeFunctionData("transferFrom", [
      investor.address,
      poolLogicProxy.address,
      (100e18).toString(),
    ]);
    await susdProxy.givenMethodReturnBool(transferFromABI, true);

    await poolLogicProxy.deposit(susd, (100e18).toString());

    const oneDollar = 1e18;
    let balanceOfABI = iERC20.encodeFunctionData("balanceOf", [poolLogicProxy.address]);
    await susdProxy.givenCalldataReturnUint(balanceOfABI, (100e18).toString());

    expect((await poolPerformanceProxy.tokenPrice(poolLogicProxy.address)).toString()).to.equal(oneDollar.toString());
    expect((await poolPerformanceProxy.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
      oneDollar.toString(),
    );

    expect((await poolPerformanceProxy.tokenPriceAdjustedForManagerFee(poolLogicProxy.address)).toString()).to.equal(
      oneDollar.toString(),
    );
    expect(
      (await poolPerformanceProxy.tokenPriceAdjustedForPerformanceAndManagerFee(poolLogicProxy.address)).toString(),
    ).to.equal(oneDollar.toString());

    const twoDollar = 2e18;
    await susdProxy.givenCalldataReturnUint(balanceOfABI, (200e18).toString());

    expect((await poolPerformanceProxy.tokenPrice(poolLogicProxy.address)).toString()).to.equal(twoDollar.toString());
    expect((await poolPerformanceProxy.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
      oneDollar.toString(),
    );

    const oneDollarSixty = 16e17;
    expect((await poolPerformanceProxy.tokenPriceAdjustedForManagerFee(poolLogicProxy.address)).toString()).to.equal(
      oneDollarSixty.toString(),
    );
    expect(
      (await poolPerformanceProxy.tokenPriceAdjustedForPerformanceAndManagerFee(poolLogicProxy.address)).toString(),
    ).to.equal((oneDollarSixty - oneDollar).toString());

    const current = (await ethers.provider.getBlock()).timestamp;
    const AggregatorV3 = await hre.artifacts.readArtifact("AggregatorV3Interface");
    const iAggregatorV3 = new ethers.utils.Interface(AggregatorV3.abi);
    const latestRoundDataABI = iAggregatorV3.encodeFunctionData("latestRoundData", []);

    // Double the usd price
    await usd_price_feed.givenCalldataReturn(
      latestRoundDataABI,
      ethers.utils.solidityPack(["uint256", "int256", "uint256", "uint256", "uint256"], [0, 200000000, 0, current, 0]),
    ); // $2

    const fourDollar = 4e18;
    // Token price is now $4
    expect((await poolPerformanceProxy.tokenPrice(poolLogicProxy.address)).toString()).to.equal(fourDollar.toString());

    // Token price adjusted for down for the direct deposit value (now $2) is $2
    expect((await poolPerformanceProxy.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
      twoDollar.toString(),
    );

    // The token price is now $4 and $3 of that is profit in the eyes of the contract, the manager is owed .375 tokens roughly $1.5 at the current token price
    // This means after minting manager fee there would be 1.375 tokens owning $4
    // $4 / 1.375 = $2.919708029
    const twoDollarNinety = ethers.BigNumber.from(BigInt((fourDollar / 1.375) * 1));
    expect(
      (await poolPerformanceProxy.tokenPriceAdjustedForManagerFee(poolLogicProxy.address)).toString(),
    ).to.be.closeTo(twoDollarNinety, 100);

    // $2.90 - minus the direct deposit of $2 = $.90
    expect(
      (await poolPerformanceProxy.tokenPriceAdjustedForPerformanceAndManagerFee(poolLogicProxy.address)).toString(),
    ).to.be.closeTo(ethers.BigNumber.from(BigInt(twoDollarNinety - twoDollar)), 100);
  });
});
