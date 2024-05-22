import { Interface } from "@ethersproject/abi";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { BigNumber } from "ethers";
import hre, { ethers, upgrades } from "hardhat";
import {
  AssetHandler,
  ERC20Guard,
  IERC20Extended__factory,
  IERC20__factory,
  IMiniChefV2__factory,
  MockContract,
  OpenAssetGuard,
  PoolFactory,
  PoolLogic,
  PoolLogic__factory,
  PoolManagerLogic,
  PoolManagerLogic__factory,
  SushiLPAssetGuard,
  SushiMiniChefV2Guard,
  SynthetixGuard,
  UniswapV2RouterGuard,
  UniswapV3RouterGuard,
  UniV2LPAggregator,
  SlippageAccumulator,
} from "../../types";
import { currentBlockTimestamp, toBytes32, units, updateChainlinkAggregators } from "../testHelpers";

// Place holder addresses
const TESTNET_DAO = "0xab0c25f17e993F90CaAaec06514A2cc28DEC340b";
const externalValidToken = "0xb79fad4ca981472442f53d16365fdf0305ffd8e9"; //random address
const externalUnsupportedToken = "0x7cea675598da73f859696b483c05a4f135b2092e"; //random address

const abiCoder = ethers.utils.defaultAbiCoder;

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
  let logicOwner: SignerWithAddress,
    manager: SignerWithAddress,
    dao: SignerWithAddress,
    investor: SignerWithAddress,
    user1: SignerWithAddress,
    user2: SignerWithAddress,
    user3: SignerWithAddress;
  let poolFactory: PoolFactory,
    poolLogic: PoolLogic,
    poolManagerLogic: PoolManagerLogic,
    poolLogicProxy: PoolLogic,
    poolManagerLogicProxy: PoolManagerLogic,
    fundAddress: string;
  let iERC20: Interface, iMiniChefV2: Interface;
  let slippageAccumulator: SlippageAccumulator;
  let synthetixGuard: SynthetixGuard,
    uniswapV2RouterGuard: UniswapV2RouterGuard,
    uniswapV3RouterGuard: UniswapV3RouterGuard,
    sushiMiniChefV2Guard: SushiMiniChefV2Guard; // contract guards
  let erc20Guard: ERC20Guard, sushiLPAssetGuard: SushiLPAssetGuard, openAssetGuard: OpenAssetGuard; // asset guards
  let addressResolver: MockContract,
    synthetix: MockContract,
    uniswapV2Router: MockContract,
    uniswapV3Router: MockContract; // integrating contracts
  let susd: string, seth: string, slink: string;
  let oneInchRouter: MockContract;
  let susdAsset: MockContract,
    susdProxy: MockContract,
    sethAsset: MockContract,
    sethProxy: MockContract,
    slinkAsset: MockContract,
    slinkProxy: MockContract;
  let sushiLPAggregator: UniV2LPAggregator; // local aggregators
  let assetHandler: AssetHandler;
  let usd_price_feed: MockContract, eth_price_feed: MockContract, link_price_feed: MockContract; // integrating aggregators
  let sushiMiniChefV2: MockContract;
  let sushiLPLinkWethAsset: MockContract;
  let quickLPLinkWethAsset: MockContract;
  let uniswapV2Factory: MockContract;
  let sushiToken: MockContract;
  let wmaticToken: MockContract;
  let aaveLendingPool: MockContract;
  let dai: MockContract;
  let usdc: MockContract;
  let aaveProtocolDataProvider: MockContract;
  let aaveLendingPoolAssetGuard: MockContract;
  let quickLPAssetGuard: MockContract;
  let sushiLPLinkWeth: string;
  let quickLPLinkWeth: string;
  let sushiLPLinkWethPoolId: number;
  let badtoken: string;

  before(async function () {
    [logicOwner, manager, dao, investor, user1, user2, user3] = await ethers.getSigners();

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
    quickLPLinkWethAsset = await MockContract.deploy();
    usd_price_feed = await MockContract.deploy();
    eth_price_feed = await MockContract.deploy();
    link_price_feed = await MockContract.deploy();
    uniswapV2Factory = await MockContract.deploy();
    sushiToken = await MockContract.deploy();
    wmaticToken = await MockContract.deploy();
    oneInchRouter = await MockContract.deploy();
    aaveLendingPool = await MockContract.deploy();
    dai = await MockContract.deploy();
    usdc = await MockContract.deploy();
    aaveProtocolDataProvider = await MockContract.deploy();
    aaveLendingPoolAssetGuard = await MockContract.deploy();
    quickLPAssetGuard = await MockContract.deploy();
    susd = susdProxy.address;
    seth = sethProxy.address;
    slink = slinkProxy.address;
    sushiLPLinkWeth = sushiLPLinkWethAsset.address;
    sushiLPLinkWethPoolId = 0; // set Sushi LP staking contract Pool Id
    quickLPLinkWeth = quickLPLinkWethAsset.address;
    badtoken = "0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB";

    // mock IAddressResolver
    const IAddressResolver = await hre.artifacts.readArtifact(
      "contracts/interfaces/synthetix/IAddressResolver.sol:IAddressResolver",
    );
    const iAddressResolver = new ethers.utils.Interface(IAddressResolver.abi);
    const getAddressABI = iAddressResolver.encodeFunctionData("getAddress", [_SYNTHETIX_KEY]);
    await addressResolver.givenCalldataReturnAddress(getAddressABI, synthetix.address);

    const IUniswapV2Router = await hre.artifacts.readArtifact(
      "contracts/interfaces/uniswapV2/IUniswapV2Router.sol:IUniswapV2Router",
    );
    const iUniswapV2Router = new ethers.utils.Interface(IUniswapV2Router.abi);
    const factoryABI = iUniswapV2Router.encodeFunctionData("factory", []);
    await uniswapV2Router.givenCalldataReturnAddress(factoryABI, uniswapV2Factory.address);

    // mock Sushi LINK-WETH LP
    const IUniswapV2Pair = await hre.artifacts.readArtifact(
      "contracts/interfaces/uniswapV2/IUniswapV2Pair.sol:IUniswapV2Pair",
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

    // mock IAaveProtocolDataProvider
    const IAaveProtocolDataProvider = await hre.artifacts.readArtifact("IAaveProtocolDataProvider");
    const iAaveProtocolDataProvider = new ethers.utils.Interface(IAaveProtocolDataProvider.abi);
    const ADDRESSES_PROVIDERABI = iAaveProtocolDataProvider.encodeFunctionData("ADDRESSES_PROVIDER", []);
    await aaveProtocolDataProvider.givenCalldataReturnAddress(ADDRESSES_PROVIDERABI, aaveProtocolDataProvider.address);

    // mock ILendingPoolAddressesProvider
    const ILendingPoolAddressesProvider = await hre.artifacts.readArtifact("ILendingPoolAddressesProvider");
    const iLendingPoolAddressesProvider = new ethers.utils.Interface(ILendingPoolAddressesProvider.abi);
    const getLendingPoolABI = iLendingPoolAddressesProvider.encodeFunctionData("getLendingPool", []);
    await aaveProtocolDataProvider.givenCalldataReturnAddress(getLendingPoolABI, aaveProtocolDataProvider.address);

    iERC20 = new ethers.utils.Interface(IERC20Extended__factory.abi);
    const decimalsABI = iERC20.encodeFunctionData("decimals", []);
    await susdProxy.givenCalldataReturnUint(decimalsABI, "18");
    await sethProxy.givenCalldataReturnUint(decimalsABI, "18");
    await slinkProxy.givenCalldataReturnUint(decimalsABI, "18");
    await sushiLPLinkWethAsset.givenCalldataReturnUint(decimalsABI, "18");
    await quickLPLinkWethAsset.givenCalldataReturnUint(decimalsABI, "18");
    await sushiToken.givenCalldataReturnUint(decimalsABI, "18");
    await wmaticToken.givenCalldataReturnUint(decimalsABI, "18");
    await aaveLendingPool.givenCalldataReturnUint(decimalsABI, "18");
    await dai.givenCalldataReturnUint(decimalsABI, "18");
    await usdc.givenCalldataReturnUint(decimalsABI, "18");
    await aaveLendingPoolAssetGuard.givenCalldataReturnUint(decimalsABI, "18");

    // Aggregators
    await updateChainlinkAggregators(usd_price_feed, eth_price_feed, link_price_feed);

    const Governance = await ethers.getContractFactory("Governance");
    const governance = await Governance.deploy();
    console.log("governance deployed to:", governance.address);

    const PoolLogicV24 = await ethers.getContractFactory("PoolLogicV24");
    const poolLogicV24 = await PoolLogicV24.deploy();
    const PoolLogic = await ethers.getContractFactory("PoolLogic");
    poolLogic = await PoolLogic.deploy();

    const PoolManagerLogicV24 = await ethers.getContractFactory("PoolManagerLogicV24");
    const poolManagerLogicV24 = await PoolManagerLogicV24.deploy();
    const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
    poolManagerLogic = await PoolManagerLogic.deploy();

    // Deploy USD Price Aggregator
    const USDPriceAggregator = await ethers.getContractFactory("USDPriceAggregator");
    const usdPriceAggregator = await USDPriceAggregator.deploy();

    // Initialize Asset Price Consumer
    const assetSusdProxy = { asset: susd, assetType: 1, aggregator: usd_price_feed.address };
    const assetSethProxy = { asset: seth, assetType: 1, aggregator: eth_price_feed.address };
    const assetSlinkProxy = { asset: slink, assetType: 1, aggregator: link_price_feed.address };
    const assetSushi = { asset: sushiToken.address, assetType: 0, aggregator: usd_price_feed.address }; // just peg price to USD
    const assetWmatic = { asset: wmaticToken.address, assetType: 0, aggregator: usd_price_feed.address }; // just peg price to USD
    const assetLendingPool = { asset: aaveLendingPool.address, assetType: 3, aggregator: usdPriceAggregator.address };
    const assetDai = { asset: dai.address, assetType: 4, aggregator: usd_price_feed.address }; // Lending enabled
    const assetUsdc = { asset: usdc.address, assetType: 4, aggregator: usd_price_feed.address }; // Lending enabled

    // Any type 4 asset needs to have this configured
    await aaveProtocolDataProvider.givenCalldataReturn(
      iAaveProtocolDataProvider.encodeFunctionData("getReserveTokensAddresses", [usdc.address]),
      abiCoder.encode(["address", "address", "address"], [ZERO_ADDRESS, ZERO_ADDRESS, ZERO_ADDRESS]),
    );

    await aaveProtocolDataProvider.givenCalldataReturn(
      iAaveProtocolDataProvider.encodeFunctionData("getReserveTokensAddresses", [dai.address]),
      abiCoder.encode(["address", "address", "address"], [ZERO_ADDRESS, ZERO_ADDRESS, ZERO_ADDRESS]),
    );

    const assetSeth = { asset: sethAsset.address, assetType: 0, aggregator: usd_price_feed.address }; // just peg price to USD
    const assetHandlerInitAssets = [
      assetSusdProxy,
      assetSethProxy,
      assetSlinkProxy,
      assetSushi,
      assetWmatic,
      assetLendingPool,
      assetDai,
      assetUsdc,
      assetSeth,
    ];

    const AssetHandlerLogic = await ethers.getContractFactory(
      "contracts/priceAggregators/AssetHandler.sol:AssetHandler",
    );
    assetHandler = <AssetHandler>await upgrades.deployProxy(AssetHandlerLogic, [assetHandlerInitAssets]);
    await assetHandler.deployed();
    console.log("assetHandler deployed to:", assetHandler.address);

    const PoolFactoryLogicV24 = await ethers.getContractFactory("PoolFactoryV24");
    const poolFactoryV24 = await upgrades.deployProxy(PoolFactoryLogicV24, [
      poolLogicV24.address,
      poolManagerLogicV24.address,
      assetHandler.address,
      dao.address,
      governance.address,
    ]);

    await poolFactoryV24.deployed();
    console.log("poolFactoryV24 deployed to:", poolFactoryV24.address);

    const PoolFactoryLogic = await ethers.getContractFactory("PoolFactory");
    poolFactory = <PoolFactory>await upgrades.upgradeProxy(poolFactoryV24.address, PoolFactoryLogic);
    console.log("poolFactory upgraded to: ", poolFactory.address);

    await poolFactory.setMaximumFee(5000, 300, 100); // 3% streaming fee, 1% entry fee.

    // Deploy Sushi LP Aggregator
    const UniV2LPAggregator = await ethers.getContractFactory("UniV2LPAggregator");
    sushiLPAggregator = await UniV2LPAggregator.deploy(sushiLPLinkWeth, poolFactory.address);
    const assetSushiLPLinkWeth = { asset: sushiLPLinkWeth, assetType: 2, aggregator: sushiLPAggregator.address };
    const assetQuickLPLinkWeth = { asset: quickLPLinkWeth, assetType: 5, aggregator: sushiLPAggregator.address };
    await assetHandler.addAssets([assetSushiLPLinkWeth, assetQuickLPLinkWeth]);

    // Deploy SlippageAccumulator
    const SlippageAccumulator = await ethers.getContractFactory("SlippageAccumulator");
    slippageAccumulator = <SlippageAccumulator>await SlippageAccumulator.deploy(poolFactory.address, "21600", 5e4); // 6 hours decay time and 5% max cumulative slippage impact
    slippageAccumulator.deployed();

    // Deploy contract guards
    const SynthetixGuard = await ethers.getContractFactory(
      "contracts/guards/contractGuards/SynthetixGuard.sol:SynthetixGuard",
    );
    synthetixGuard = <SynthetixGuard>await SynthetixGuard.deploy(addressResolver.address);
    synthetixGuard.deployed();

    const UniswapV2RouterGuard = await ethers.getContractFactory(
      "contracts/guards/contractGuards/UniswapV2RouterGuard.sol:UniswapV2RouterGuard",
    );
    uniswapV2RouterGuard = <UniswapV2RouterGuard>await UniswapV2RouterGuard.deploy(slippageAccumulator.address);
    uniswapV2RouterGuard.deployed();

    const UniswapV3RouterGuard = await ethers.getContractFactory(
      "contracts/guards/contractGuards/uniswapV3/UniswapV3RouterGuard.sol:UniswapV3RouterGuard",
    );
    uniswapV3RouterGuard = <UniswapV3RouterGuard>await UniswapV3RouterGuard.deploy(slippageAccumulator.address);
    uniswapV3RouterGuard.deployed();

    const SushiMiniChefV2Guard = await ethers.getContractFactory(
      "contracts/guards/contractGuards/SushiMiniChefV2Guard.sol:SushiMiniChefV2Guard",
    );
    sushiMiniChefV2Guard = <SushiMiniChefV2Guard>(
      await SushiMiniChefV2Guard.deploy([sushiToken.address, wmaticToken.address])
    );
    sushiMiniChefV2Guard.deployed();

    const OneInchV4Guard = await ethers.getContractFactory(
      "contracts/guards/contractGuards/OneInchV4Guard.sol:OneInchV4Guard",
    );
    const oneInchV4Guard = await OneInchV4Guard.deploy(slippageAccumulator.address);
    oneInchV4Guard.deployed();

    // Deploy asset guards
    const ERC20Guard = await ethers.getContractFactory("contracts/guards/assetGuards/ERC20Guard.sol:ERC20Guard");
    erc20Guard = <ERC20Guard>await ERC20Guard.deploy();
    erc20Guard.deployed();

    const LendingEnabledAssetGuard = await ethers.getContractFactory("LendingEnabledAssetGuard");
    const lendingEnabledAssetGuard = await LendingEnabledAssetGuard.deploy();
    await lendingEnabledAssetGuard.deployed();

    const SushiLPAssetGuard = await ethers.getContractFactory(
      "contracts/guards/assetGuards/SushiLPAssetGuard.sol:SushiLPAssetGuard",
    );
    sushiLPAssetGuard = <SushiLPAssetGuard>await SushiLPAssetGuard.deploy(sushiMiniChefV2.address); // initialise with Sushi staking pool Id
    sushiLPAssetGuard.deployed();

    const OpenAssetGuard = await ethers.getContractFactory(
      "contracts/guards/assetGuards/OpenAssetGuard.sol:OpenAssetGuard",
    );
    openAssetGuard = <OpenAssetGuard>await OpenAssetGuard.deploy([externalValidToken]); // initialise with random external token
    openAssetGuard.deployed();

    await governance.setAssetGuard(0, erc20Guard.address);
    await governance.setAssetGuard(1, erc20Guard.address);
    await governance.setAssetGuard(2, sushiLPAssetGuard.address);
    await governance.setAssetGuard(3, aaveLendingPoolAssetGuard.address);
    await governance.setAssetGuard(4, lendingEnabledAssetGuard.address);
    await governance.setAssetGuard(5, quickLPAssetGuard.address);
    await governance.setContractGuard(synthetix.address, synthetixGuard.address);
    await governance.setContractGuard(uniswapV2Router.address, uniswapV2RouterGuard.address);
    await governance.setContractGuard(uniswapV3Router.address, uniswapV3RouterGuard.address);
    await governance.setContractGuard(oneInchRouter.address, oneInchV4Guard.address);
    await governance.setContractGuard(sushiMiniChefV2.address, sushiMiniChefV2Guard.address);
    await governance.setAddresses([
      {
        name: toBytes32("openAssetGuard"),
        destination: openAssetGuard.address,
      },
      {
        name: toBytes32("aaveProtocolDataProviderV2"),
        destination: aaveProtocolDataProvider.address,
      },
    ]);

    const openAssetGuardSetting = await poolFactory.getAddress(toBytes32("openAssetGuard"));
    console.log("openAssetGuardSetting:", openAssetGuardSetting);
  });

  it("should be able to upgrade/set implementation logic", async function () {
    await expect(poolFactory.connect(user1).setLogic(poolLogic.address, poolManagerLogic.address)).to.be.revertedWith(
      "caller is not the owner",
    );
    await poolFactory.setLogic(poolLogic.address, poolManagerLogic.address);

    const poolManagerLogicAddress = await poolFactory.getLogic(1);
    expect(poolManagerLogicAddress).to.equal(poolManagerLogic.address);

    const poolLogicAddress = await poolFactory.getLogic(2);
    expect(poolLogicAddress).to.equal(poolLogic.address);
  });

  it("Should be able to set pool storage version", async function () {
    await expect(poolFactory.connect(user1).setPoolStorageVersion(POOL_STORAGE_VERSION)).to.be.revertedWith(
      "caller is not the owner",
    );

    await poolFactory.setPoolStorageVersion(POOL_STORAGE_VERSION);

    const poolStorageVersion = await poolFactory.poolStorageVersion();
    expect(poolStorageVersion).to.equal(POOL_STORAGE_VERSION);
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
        {
          asset: susd,
          isDeposit: true,
        },
        {
          asset: seth,
          isDeposit: true,
        },
      ],
    );

    console.log("Passed poolManagerLogic Init!");

    await expect(
      poolFactory.createFund(false, manager.address, "Barren Wuffet", "Test Fund", "DHTF", "6000", "200", [
        {
          asset: susd,
          isDeposit: true,
        },
        {
          asset: seth,
          isDeposit: true,
        },
      ]),
    ).to.be.revertedWith("invalid manager fee");

    console.log("Creating Fund...");

    const fundCreatedEvent = new Promise((resolve, reject) => {
      poolFactory.once(
        "FundCreated",
        (
          fundAddress,
          isPoolPrivate,
          fundName,
          managerName,
          manager,
          time,
          performanceFeeNumerator,
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
            performanceFeeNumerator: performanceFeeNumerator,
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
      poolFactory.createFund(false, manager.address, "Barren Wuffet", "Test Fund", "DHTF", "6000", "200", [
        {
          asset: susd,
          isDeposit: false,
        },
        {
          asset: seth,
          isDeposit: true,
        },
      ]),
    ).to.be.revertedWith("invalid manager fee");

    await expect(
      poolFactory.createFund(false, manager.address, "Barren Wuffet", "Test Fund", "DHTF", "5000", "200", [
        {
          asset: susd,
          isDeposit: false,
        },
        {
          asset: seth,
          isDeposit: false,
        },
      ]),
    ).to.be.revertedWith("at least one deposit asset"); // at least one deposit asset

    await poolFactory.createFund(false, manager.address, "Barren Wuffet", "Test Fund", "DHTF", "5000", "200", [
      {
        asset: seth,
        isDeposit: false,
      },
      {
        asset: susd,
        isDeposit: true,
      },
    ]);

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const event: any = await fundCreatedEvent;

    fundAddress = event.fundAddress;
    console.log("fundAddress: ", fundAddress);
    expect(event.isPoolPrivate).to.be.false;
    expect(event.fundName).to.equal("Test Fund");
    // expect(event.fundSymbol).to.equal('DHTF');
    expect(event.managerName).to.equal("Barren Wuffet");
    expect(event.manager).to.equal(manager.address);
    expect(event.performanceFeeNumerator.toString()).to.equal("5000");
    expect(event.managerFeeNumerator.toString()).to.equal("200");
    expect(event.managerFeeDenominator.toString()).to.equal("10000");

    const deployedFunds = await poolFactory.getDeployedFunds();
    const deployedFundsLength = deployedFunds.length;
    expect(deployedFundsLength).to.equal(1);

    const isPool = await poolFactory.isPool(fundAddress);
    expect(isPool).to.be.true;

    const poolManagerLogicAddress = await poolFactory.getLogic(1);
    expect(poolManagerLogicAddress).to.equal(poolManagerLogic.address);

    const poolLogicAddress = await poolFactory.getLogic(2);
    expect(poolLogicAddress).to.equal(poolLogic.address);

    poolLogicProxy = await PoolLogic__factory.connect(fundAddress, logicOwner);
    const poolManagerLogicProxyAddress = await poolLogicProxy.poolManagerLogic();
    poolManagerLogicProxy = await PoolManagerLogic__factory.connect(poolManagerLogicProxyAddress, logicOwner);

    // check create fund works correctly for AssetAdded event (fundAddress = poolLogic)
    // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
    expect(poolManagerLogicProxy.filters.AssetAdded(poolLogicProxy.address).topics![1]).to.be.equal(
      ethers.utils.hexZeroPad(poolLogicProxy.address, 32).toLowerCase(),
    );

    //default assets are supported
    const supportedAssets = await poolManagerLogicProxy.getSupportedAssets();
    expect(supportedAssets.length).to.equal(2);
    expect(await poolManagerLogicProxy.isSupportedAsset(susd)).to.be.true;
    expect(await poolManagerLogicProxy.isSupportedAsset(seth)).to.be.true;

    //Other assets are not supported
    expect(await poolManagerLogicProxy.isSupportedAsset(slink)).to.be.false;

    // check pool storage version
    const poolVersion = await poolFactory.poolVersion(poolLogicProxy.address);
    expect(poolVersion).to.equal(POOL_STORAGE_VERSION);

    // mock IMiniChefV2
    iMiniChefV2 = new ethers.utils.Interface(IMiniChefV2__factory.abi);
    const userInfo = iMiniChefV2.encodeFunctionData("userInfo", [sushiLPLinkWethPoolId, poolLogicProxy.address]);
    const amountLPStaked = "0";
    const amountRewarded = "0";
    await sushiMiniChefV2.givenCalldataReturn(
      userInfo,
      abiCoder.encode(["uint256", "uint256"], [amountLPStaked, amountRewarded]),
    );
    const poolLengthABI = iMiniChefV2.encodeFunctionData("poolLength", []);
    await sushiMiniChefV2.givenCalldataReturnUint(poolLengthABI, "1");
    const lpTokenABI = iMiniChefV2.encodeFunctionData("lpToken", [sushiLPLinkWethPoolId]);
    await sushiMiniChefV2.givenCalldataReturnAddress(lpTokenABI, sushiLPLinkWeth);
  });

  it("should be able to manage assets", async function () {
    await expect(
      poolManagerLogicProxy.connect(user1).changeAssets(
        [
          {
            asset: slink,
            isDeposit: false,
          },
        ],
        [],
      ),
    ).to.be.revertedWith("only manager, trader or owner");

    const poolManagerLogicManagerProxy = poolManagerLogicProxy.connect(manager);
    const poolManagerLogicUser1Proxy = poolManagerLogicProxy.connect(user1);

    // Can add asset
    await poolManagerLogicManagerProxy.changeAssets(
      [
        {
          asset: slink,
          isDeposit: false,
        },
      ],
      [],
    );

    let supportedAssets = await poolManagerLogicManagerProxy.getSupportedAssets();
    let numberOfSupportedAssets = supportedAssets.length;
    expect(numberOfSupportedAssets).to.eq(3);

    let depositAssets = await poolManagerLogicManagerProxy.getDepositAssets();
    let numberOfDepositAssets = depositAssets.length;
    expect(numberOfDepositAssets).to.be.equal(1);

    // Can add asset to maximum
    await poolManagerLogicManagerProxy.changeAssets(
      [
        {
          asset: sushiLPLinkWeth,
          isDeposit: false,
        },
      ],
      [],
    );
    await poolManagerLogicManagerProxy.changeAssets(
      [
        {
          asset: quickLPLinkWeth,
          isDeposit: false,
        },
      ],
      [],
    );
    await poolManagerLogicManagerProxy.changeAssets(
      [
        {
          asset: sushiToken.address,
          isDeposit: false,
        },
      ],
      [],
    );
    await poolManagerLogicManagerProxy.changeAssets(
      [
        {
          asset: wmaticToken.address,
          isDeposit: false,
        },
      ],
      [],
    );
    await poolManagerLogicManagerProxy.changeAssets(
      [
        {
          asset: aaveLendingPool.address,
          isDeposit: false,
        },
      ],
      [],
    );
    await poolManagerLogicManagerProxy.changeAssets(
      [
        {
          asset: dai.address,
          isDeposit: false,
        },
      ],
      [],
    );
    await poolManagerLogicManagerProxy.changeAssets(
      [
        {
          asset: usdc.address,
          isDeposit: false,
        },
      ],
      [],
    );

    supportedAssets = await poolManagerLogicManagerProxy.getSupportedAssets();
    numberOfSupportedAssets = supportedAssets.length;
    expect(numberOfSupportedAssets).to.eq(10);

    // Check assets ordering
    expect(supportedAssets[0][0]).to.equal(quickLPLinkWeth);
    expect(supportedAssets[1][0]).to.equal(dai.address);
    expect(supportedAssets[2][0]).to.equal(usdc.address);
    expect(supportedAssets[3][0]).to.equal(aaveLendingPool.address);
    expect(supportedAssets[4][0]).to.equal(sushiLPLinkWeth);
    expect(supportedAssets[5][0]).to.equal(seth);
    expect(supportedAssets[6][0]).to.equal(susd);
    expect(supportedAssets[7][0]).to.equal(slink);
    expect(supportedAssets[8][0]).to.equal(sushiToken.address);
    expect(supportedAssets[9][0]).to.equal(wmaticToken.address);
    await expect(
      poolManagerLogicManagerProxy.changeAssets(
        [
          {
            asset: sethAsset.address,
            isDeposit: false,
          },
        ],
        [],
      ),
    ).to.be.revertedWith("maximum assets reached");

    // Can remove asset back to before
    await poolManagerLogicManagerProxy.changeAssets([], [sushiLPLinkWeth]);
    // Check assets ordering
    supportedAssets = await poolManagerLogicManagerProxy.getSupportedAssets();
    expect(supportedAssets[0][0]).to.equal(quickLPLinkWeth);
    expect(supportedAssets[1][0]).to.equal(dai.address);
    expect(supportedAssets[2][0]).to.equal(usdc.address);
    expect(supportedAssets[3][0]).to.equal(aaveLendingPool.address);
    expect(supportedAssets[4][0]).to.equal(seth);
    expect(supportedAssets[5][0]).to.equal(susd);
    expect(supportedAssets[6][0]).to.equal(slink);
    expect(supportedAssets[7][0]).to.equal(sushiToken.address);
    expect(supportedAssets[8][0]).to.equal(wmaticToken.address);
    await poolManagerLogicManagerProxy.changeAssets([], [aaveLendingPool.address]);
    supportedAssets = await poolManagerLogicManagerProxy.getSupportedAssets();
    expect(supportedAssets[0][0]).to.equal(quickLPLinkWeth);
    expect(supportedAssets[1][0]).to.equal(dai.address);
    expect(supportedAssets[2][0]).to.equal(usdc.address);
    expect(supportedAssets[3][0]).to.equal(seth);
    expect(supportedAssets[4][0]).to.equal(susd);
    expect(supportedAssets[5][0]).to.equal(slink);
    expect(supportedAssets[6][0]).to.equal(sushiToken.address);
    expect(supportedAssets[7][0]).to.equal(wmaticToken.address);
    await poolManagerLogicManagerProxy.changeAssets([], [usdc.address]);
    supportedAssets = await poolManagerLogicManagerProxy.getSupportedAssets();
    expect(supportedAssets[0][0]).to.equal(quickLPLinkWeth);
    expect(supportedAssets[1][0]).to.equal(dai.address);
    expect(supportedAssets[2][0]).to.equal(seth);
    expect(supportedAssets[3][0]).to.equal(susd);
    expect(supportedAssets[4][0]).to.equal(slink);
    expect(supportedAssets[5][0]).to.equal(sushiToken.address);
    expect(supportedAssets[6][0]).to.equal(wmaticToken.address);
    await poolManagerLogicManagerProxy.changeAssets([], [dai.address]);
    supportedAssets = await poolManagerLogicManagerProxy.getSupportedAssets();
    expect(supportedAssets[0][0]).to.equal(quickLPLinkWeth);
    expect(supportedAssets[1][0]).to.equal(seth);
    expect(supportedAssets[2][0]).to.equal(susd);
    expect(supportedAssets[3][0]).to.equal(slink);
    expect(supportedAssets[4][0]).to.equal(sushiToken.address);
    expect(supportedAssets[5][0]).to.equal(wmaticToken.address);
    await poolManagerLogicManagerProxy.changeAssets([], [sushiToken.address]);
    supportedAssets = await poolManagerLogicManagerProxy.getSupportedAssets();
    expect(supportedAssets[0][0]).to.equal(quickLPLinkWeth);
    expect(supportedAssets[1][0]).to.equal(seth);
    expect(supportedAssets[2][0]).to.equal(susd);
    expect(supportedAssets[3][0]).to.equal(slink);
    expect(supportedAssets[4][0]).to.equal(wmaticToken.address);
    await poolManagerLogicManagerProxy.changeAssets([], [wmaticToken.address]);
    supportedAssets = await poolManagerLogicManagerProxy.getSupportedAssets();
    expect(supportedAssets[0][0]).to.equal(quickLPLinkWeth);
    expect(supportedAssets[1][0]).to.equal(seth);
    expect(supportedAssets[2][0]).to.equal(susd);
    expect(supportedAssets[3][0]).to.equal(slink);
    await poolManagerLogicManagerProxy.changeAssets([], [quickLPLinkWeth]);
    supportedAssets = await poolManagerLogicManagerProxy.getSupportedAssets();
    expect(supportedAssets[0][0]).to.equal(seth);
    expect(supportedAssets[1][0]).to.equal(susd);
    expect(supportedAssets[2][0]).to.equal(slink);
    numberOfSupportedAssets = supportedAssets.length;
    expect(numberOfSupportedAssets).to.eq(3);

    // Can not remove persist asset
    await expect(poolManagerLogicUser1Proxy.changeAssets([], [slink])).to.be.revertedWith(
      "only manager, trader or owner",
    );

    // Can't add invalid asset
    const invalid_synth_asset = "0x823bE81bbF96BEc0e25CA13170F5AaCb5B79ba83";
    await expect(
      poolManagerLogicManagerProxy.changeAssets(
        [
          {
            asset: invalid_synth_asset,
            isDeposit: false,
          },
        ],
        [],
      ),
    ).to.be.revertedWith("invalid asset");

    // Can't remove asset with non zero balance
    // mock IERC20 balanceOf to return non zero
    const balanceOfABI = iERC20.encodeFunctionData("balanceOf", [poolLogicProxy.address]);
    await slinkProxy.givenCalldataReturnUint(balanceOfABI, 1);

    await expect(poolManagerLogicManagerProxy.changeAssets([], [slink])).to.be.revertedWith(
      "cannot remove non-empty asset",
    );

    // Can enable deposit asset
    await poolManagerLogicManagerProxy.changeAssets(
      [
        {
          asset: slink,
          isDeposit: true,
        },
      ],
      [],
    );
    expect(await poolManagerLogicProxy.isDepositAsset(slink)).to.be.true;

    depositAssets = await poolManagerLogicManagerProxy.getDepositAssets();
    numberOfDepositAssets = depositAssets.length;
    expect(numberOfDepositAssets).to.be.equal(2);

    // Can disable deposit asset
    await poolManagerLogicManagerProxy.changeAssets(
      [
        {
          asset: slink,
          isDeposit: false,
        },
      ],
      [],
    );
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

  it("should return correct values ", async function () {
    const supportedAssets = await poolManagerLogicProxy.getSupportedAssets();
    const numberOfSupportedAssets = supportedAssets.length;
    const depositAssets = await poolManagerLogicProxy.getDepositAssets();
    const numberOfDepositAssets = depositAssets.length;
    expect(numberOfSupportedAssets).to.gte(numberOfDepositAssets);
    expect(depositAssets[0]).to.eq(susd);
    const fundComposition = await poolManagerLogicProxy.getFundComposition();
    expect(fundComposition.assets.length).to.eq(numberOfSupportedAssets);
    expect(fundComposition.balances.length).to.eq(numberOfSupportedAssets);
    expect(fundComposition.rates.length).to.eq(numberOfSupportedAssets);
  });

  it("should be able to deposit", async function () {
    const depositEvent = new Promise((resolve, reject) => {
      poolLogicProxy.once(
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
    const transferFromABI = iERC20.encodeFunctionData("transferFrom", [
      investor.address,
      poolLogicProxy.address,
      (100e18).toString(),
    ]);
    await susdProxy.givenCalldataReturnBool(transferFromABI, true);

    const totalFundValue = await poolManagerLogicProxy.totalFundValue();
    // As default there's susd and seth and each return 1 by IExchangeRates
    expect(totalFundValue.toString()).to.equal("0");

    await expect(poolLogicProxy.deposit(slink, (100e18).toString())).to.be.revertedWith("invalid deposit asset");
    await poolLogicProxy.connect(investor).deposit(susd, (100e18).toString());

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const event: any = await depositEvent;
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
    const withdrawalEvent = new Promise((resolve, reject) => {
      poolLogicProxy.once(
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
    const balanceOfABI = iERC20.encodeFunctionData("balanceOf", [poolLogicProxy.address]);
    await susdProxy.givenCalldataReturnUint(balanceOfABI, (100e18).toString());

    // Withdraw 50%
    const withdrawAmount = units(50);
    const totalSupply = await poolLogicProxy.totalSupply();
    const totalFundValue = await poolManagerLogicProxy.totalFundValue();
    const totalFundsPreWithdrawal = await poolLogicProxy.balanceOf(investor.address);
    const totalSupplyPreWithdrawal = await poolLogicProxy.totalSupply();

    await poolManagerLogicProxy.connect(manager).setFeeNumerator(0, 0, 0);

    await expect(poolLogicProxy.connect(investor).withdraw(withdrawAmount.toString())).to.be.revertedWith(
      "cooldown active",
    );

    // await poolFactory.setExitCooldown(0);
    ethers.provider.send("evm_increaseTime", [3600 * 24]); // add 1 day

    await poolLogicProxy.connect(investor).withdraw(withdrawAmount.toString());

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const event: any = await withdrawalEvent;

    const fundTokensWithdrawn = withdrawAmount;
    const valueWithdrawn = fundTokensWithdrawn.mul(totalFundValue).div(totalSupply);
    expect(event.fundAddress).to.equal(poolLogicProxy.address);
    expect(event.investor).to.equal(investor.address);
    expect(event.valueWithdrawn).to.equal(valueWithdrawn);
    expect(event.fundTokensWithdrawn).to.equal(withdrawAmount.toString());
    expect(event.totalInvestorFundTokens).to.equal(totalFundsPreWithdrawal.sub(withdrawAmount).toString());
    expect(event.fundValue).to.equal(totalFundValue.sub(valueWithdrawn));

    expect(event.totalSupply).to.equal(totalSupplyPreWithdrawal.sub(withdrawAmount).toString());
    const withdrawnAsset = event.withdrawnAssets[0];
    expect(withdrawnAsset[0]).to.equal(susd);
    expect(withdrawnAsset[1]).to.equal(valueWithdrawn);
    expect(withdrawnAsset[2]).to.equal(false);

    await poolFactory.setMaximumPerformanceFeeNumeratorChange(5000);
    await poolManagerLogicProxy.connect(manager).announceFeeIncrease(5000, 200, 0); // increase streaming fee to 2%
    await ethers.provider.send("evm_increaseTime", [3600 * 24 * 7 * 4]); // add 4 weeks
    await ethers.provider.send("evm_mine", []);
    await updateChainlinkAggregators(usd_price_feed, eth_price_feed, link_price_feed);
    await poolManagerLogicProxy.connect(manager).commitFeeIncrease();
    await poolFactory.setMaximumPerformanceFeeNumeratorChange(1000);
  });

  it("should be able to manage pool", async function () {
    await poolFactory.createFund(true, manager.address, "Barren Wuffet", "Test Fund", "DHTF", "5000", "200", [
      {
        asset: susd,
        isDeposit: true,
      },
      {
        asset: seth,
        isDeposit: true,
      },
    ]);

    const deployedFunds = await poolFactory.getDeployedFunds();
    const deployedFundsLength = deployedFunds.length;
    const fundAddress = deployedFunds[deployedFundsLength - 1];
    const poolLogicPrivateProxy = await PoolLogic__factory.connect(fundAddress, logicOwner);
    const poolManagerLogicPrivateProxy = await PoolManagerLogic__factory.connect(
      await poolLogicPrivateProxy.poolManagerLogic(),
      logicOwner,
    );

    const transferFromABI = iERC20.encodeFunctionData("transferFrom", [
      investor.address,
      poolLogicPrivateProxy.address,
      (100e18).toString(),
    ]);
    await susdProxy.givenMethodReturnBool(transferFromABI, true);

    // Can't deposit when not being a member
    await expect(poolLogicPrivateProxy.deposit(susd, (100e18).toString())).to.be.revertedWith("only members allowed");

    await expect(poolManagerLogicPrivateProxy.addMember(logicOwner.address)).to.be.revertedWith("only manager");

    const poolManagerLogicPrivateManagerProxy = poolManagerLogicPrivateProxy.connect(manager);

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

  it("should be able to manage assets 2", async function () {
    await expect(
      poolManagerLogicProxy.connect(user1).changeAssets(
        [
          {
            asset: slink,
            isDeposit: false,
          },
        ],
        [],
      ),
    ).to.be.revertedWith("only manager, trader or owner");

    const poolManagerLogicManagerProxy = poolManagerLogicProxy.connect(manager);
    const poolManagerLogicUser1Proxy = poolManagerLogicProxy.connect(user1);

    // Can add asset
    await poolManagerLogicManagerProxy.changeAssets(
      [
        {
          asset: slink,
          isDeposit: false,
        },
      ],
      [],
    );

    let supportedAssets = await poolManagerLogicManagerProxy.getSupportedAssets();
    let numberOfSupportedAssets = supportedAssets.length;
    expect(numberOfSupportedAssets).to.eq(3);

    let depositAssets = await poolManagerLogicManagerProxy.getDepositAssets();
    let numberOfDepositAssets = depositAssets.length;
    expect(numberOfDepositAssets).to.be.equal(1);

    // Can add asset to maximum
    // Initialize Asset Price Consumer
    const assets = [
      {
        asset: susdAsset.address,
        aggregator: susdAsset.address,
        assetType: 2,
      },
      {
        asset: sethAsset.address,
        aggregator: sethAsset.address,
        assetType: 2,
      },
      {
        asset: slinkAsset.address,
        aggregator: slinkAsset.address,
        assetType: 0,
      },
      {
        asset: usd_price_feed.address,
        aggregator: usd_price_feed.address,
        assetType: 2,
      },
      {
        asset: eth_price_feed.address,
        aggregator: eth_price_feed.address,
        assetType: 0,
      },
    ];
    await assetHandler.addAssets(assets);
    await poolManagerLogicManagerProxy.changeAssets(
      [
        {
          asset: sushiLPLinkWeth,
          isDeposit: false,
        },
      ],
      [],
    );
    await poolManagerLogicManagerProxy.changeAssets(
      [
        {
          asset: susdAsset.address,
          isDeposit: false,
        },
      ],
      [],
    );
    await poolManagerLogicManagerProxy.changeAssets(
      [
        {
          asset: sethAsset.address,
          isDeposit: false,
        },
      ],
      [],
    );
    await poolManagerLogicManagerProxy.changeAssets(
      [
        {
          asset: slinkAsset.address,
          isDeposit: false,
        },
      ],
      [],
    );
    await poolManagerLogicManagerProxy.changeAssets(
      [
        {
          asset: sushiToken.address,
          isDeposit: false,
        },
      ],
      [],
    );
    await poolManagerLogicManagerProxy.changeAssets(
      [
        {
          asset: wmaticToken.address,
          isDeposit: false,
        },
      ],
      [],
    );
    await poolManagerLogicManagerProxy.changeAssets(
      [
        {
          asset: usd_price_feed.address,
          isDeposit: false,
        },
      ],
      [],
    );

    supportedAssets = await poolManagerLogicManagerProxy.getSupportedAssets();
    numberOfSupportedAssets = supportedAssets.length;
    expect(numberOfSupportedAssets).to.eq(10);

    // Check assets ordering
    expect(supportedAssets[1][0]).to.equal(susdAsset.address);
    expect(supportedAssets[2][0]).to.equal(sethAsset.address);
    expect(supportedAssets[3][0]).to.equal(usd_price_feed.address);
    expect(supportedAssets[7][0]).to.equal(slinkAsset.address);

    await expect(
      poolManagerLogicManagerProxy.changeAssets(
        [
          {
            asset: eth_price_feed.address,
            isDeposit: false,
          },
        ],
        [],
      ),
    ).to.be.revertedWith("maximum assets reached");

    // Can remove asset back to before
    await poolManagerLogicManagerProxy.changeAssets([], [sushiLPLinkWeth]);
    await poolManagerLogicManagerProxy.changeAssets([], [susdAsset.address]);
    await poolManagerLogicManagerProxy.changeAssets([], [sethAsset.address]);
    await poolManagerLogicManagerProxy.changeAssets([], [slinkAsset.address]);
    await poolManagerLogicManagerProxy.changeAssets([], [sushiToken.address]);
    await poolManagerLogicManagerProxy.changeAssets([], [wmaticToken.address]);
    await poolManagerLogicManagerProxy.changeAssets([], [usd_price_feed.address]);
    supportedAssets = await poolManagerLogicManagerProxy.getSupportedAssets();
    numberOfSupportedAssets = supportedAssets.length;
    expect(numberOfSupportedAssets).to.eq(3);

    // Can not remove persist asset
    await expect(poolManagerLogicUser1Proxy.changeAssets([], [slink])).to.be.revertedWith(
      "only manager, trader or owner",
    );

    // Can't add invalid asset
    const invalid_synth_asset = "0x823bE81bbF96BEc0e25CA13170F5AaCb5B79ba83";
    await expect(
      poolManagerLogicManagerProxy.changeAssets(
        [
          {
            asset: invalid_synth_asset,
            isDeposit: false,
          },
        ],
        [],
      ),
    ).to.be.revertedWith("invalid asset");

    // Can't remove asset with non zero balance
    // mock IERC20 balanceOf to return non zero
    const balanceOfABI = iERC20.encodeFunctionData("balanceOf", [poolLogicProxy.address]);
    await slinkProxy.givenCalldataReturnUint(balanceOfABI, 1);

    await expect(poolManagerLogicManagerProxy.changeAssets([], [slink])).to.be.revertedWith(
      "cannot remove non-empty asset",
    );

    // Can enable deposit asset
    await poolManagerLogicManagerProxy.changeAssets(
      [
        {
          asset: slink,
          isDeposit: true,
        },
      ],
      [],
    );
    expect(await poolManagerLogicProxy.isDepositAsset(slink)).to.be.true;

    depositAssets = await poolManagerLogicManagerProxy.getDepositAssets();
    numberOfDepositAssets = depositAssets.length;
    expect(numberOfDepositAssets).to.be.equal(2);

    // Can disable deposit asset
    await poolManagerLogicManagerProxy.changeAssets(
      [
        {
          asset: slink,
          isDeposit: false,
        },
      ],
      [],
    );
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
    await expect(poolManagerLogicProxy.announceFeeIncrease(4000, 300, 25)).to.be.revertedWith("only manager");

    const poolManagerLogicManagerProxy = poolManagerLogicProxy.connect(manager);

    await expect(poolManagerLogicManagerProxy.announceFeeIncrease(6100, 400, 25)).to.be.revertedWith(
      "exceeded allowed increase",
    );
    await expect(poolManagerLogicManagerProxy.announceFeeIncrease(4000, 400, 25)).to.be.revertedWith(
      "exceeded allowed increase",
    );

    //Can set manager fee
    await poolManagerLogicManagerProxy.announceFeeIncrease(4000, 250, 25); // increase streaming fee to 2.5% and entry fees to 0.25%

    await expect(poolManagerLogicManagerProxy.commitFeeIncrease()).to.be.revertedWith("fee increase delay active");

    await ethers.provider.send("evm_increaseTime", [3600 * 24 * 7 * 4]); // add 4 weeks
    await ethers.provider.send("evm_mine", []);
    await updateChainlinkAggregators(usd_price_feed, eth_price_feed, link_price_feed);

    await poolManagerLogicManagerProxy.commitFeeIncrease();

    let [performanceFeeNumerator, managerFeeNumerator, entryFeeNumerator, managerFeeDenominator] =
      await poolManagerLogicManagerProxy.getFee();
    expect(performanceFeeNumerator.toString()).to.equal("4000");
    expect(managerFeeNumerator.toString()).to.equal("250");
    expect(managerFeeDenominator.toString()).to.equal("10000");
    expect(entryFeeNumerator.toString()).to.equal("25");

    await expect(poolManagerLogicProxy.setFeeNumerator(3000, 200, 25)).to.be.revertedWith("only manager");
    await expect(poolManagerLogicManagerProxy.setFeeNumerator(5000, 200, 25)).to.be.revertedWith(
      "manager fee too high",
    );
    await expect(poolManagerLogicManagerProxy.setFeeNumerator(3000, 300, 25)).to.be.revertedWith(
      "manager fee too high",
    );
    await expect(poolManagerLogicManagerProxy.setFeeNumerator(3000, 300, 100)).to.be.revertedWith(
      "manager fee too high",
    );

    await poolManagerLogicManagerProxy.setFeeNumerator(3000, 200, 0);
    [performanceFeeNumerator, managerFeeNumerator, entryFeeNumerator, managerFeeDenominator] =
      await poolManagerLogicManagerProxy.getFee();
    expect(performanceFeeNumerator.toString()).to.equal("3000");
    expect(managerFeeNumerator.toString()).to.equal("200");
    expect(managerFeeDenominator.toString()).to.equal("10000");
    expect(entryFeeNumerator.toString()).to.equal("0");
  });

  beforeEach(async () => {
    const current = (await ethers.provider.getBlock(await ethers.provider.getBlockNumber())).timestamp;
    const AggregatorV3 = await hre.artifacts.readArtifact("AggregatorV3Interface");
    const iAggregatorV3 = new ethers.utils.Interface(AggregatorV3.abi);
    const latestRoundDataABI = iAggregatorV3.encodeFunctionData("latestRoundData", []);

    await usd_price_feed.givenCalldataReturn(
      latestRoundDataABI,
      ethers.utils.solidityPack(["uint256", "int256", "uint256", "uint256", "uint256"], [0, 100000000, 0, current, 0]),
    ); // $1
    await eth_price_feed.givenCalldataReturn(
      latestRoundDataABI,
      ethers.utils.solidityPack(
        ["uint256", "int256", "uint256", "uint256", "uint256"],
        [0, 200000000000, 0, current, 0],
      ),
    ); // $2000
    // await link_price_feed.givenCalldataReturn(
    //   latestRoundDataABI,
    //   ethers.utils.solidityPack(["uint256", "int256", "uint256", "uint256", "uint256"], [0, 3500000000, 0, current, 0]),
    // ); // $35
  });

  // Synthetix transaction guard
  it("Only manager or trader can execute transaction", async () => {
    const sourceKey = susdKey;
    const sourceAmount = (100e18).toString();
    const destinationKey = sethKey;
    const daoAddress = await poolFactory.owner();
    const trackingCode = "0x4448454447450000000000000000000000000000000000000000000000000000"; // DHEDGE

    const ISynthetix = await hre.artifacts.readArtifact("contracts/interfaces/synthetix/ISynthetix.sol:ISynthetix");
    const iSynthetix = new ethers.utils.Interface(ISynthetix.abi);
    const exchangeWithTrackingABI = iSynthetix.encodeFunctionData("exchangeWithTracking", [
      sourceKey,
      sourceAmount,
      destinationKey,
      daoAddress,
      trackingCode,
    ]);

    await expect(
      poolLogicProxy.connect(logicOwner).execTransaction(synthetix.address, exchangeWithTrackingABI),
    ).to.be.revertedWith("only manager or trader or public function");
  });

  it("Should exec transaction", async () => {
    const poolLogicManagerProxy = poolLogicProxy.connect(manager);

    const exchangeEvent = new Promise((resolve, reject) => {
      synthetixGuard.once(
        "ExchangeFrom",
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

    const sourceKey = susdKey;
    const sourceAmount = (100e18).toString();
    const destinationKey = sethKey;
    const daoAddress = await poolFactory.owner();
    const trackingCode = "0x4448454447450000000000000000000000000000000000000000000000000000"; // DHEDGE

    const ISynthetix = await hre.artifacts.readArtifact("contracts/interfaces/synthetix/ISynthetix.sol:ISynthetix");
    const iSynthetix = new ethers.utils.Interface(ISynthetix.abi);
    const exchangeWithTrackingABI = iSynthetix.encodeFunctionData("exchangeWithTracking", [
      sourceKey,
      sourceAmount,
      destinationKey,
      daoAddress,
      trackingCode,
    ]);

    await synthetix.givenCalldataRevert(exchangeWithTrackingABI);

    await expect(poolLogicManagerProxy.execTransaction(synthetix.address, exchangeWithTrackingABI)).to.be.reverted;

    await synthetix.givenCalldataReturnUint(exchangeWithTrackingABI, (1e18).toString());
    await poolLogicManagerProxy.execTransaction(synthetix.address, exchangeWithTrackingABI);

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const event: any = await exchangeEvent;
    expect(event.sourceAsset).to.equal(susd);
    expect(event.sourceAmount).to.equal((100e18).toString());
    expect(event.destinationAsset).to.equal(seth);
  });

  it("Should revert when empty transactions to execute are passed", async () => {
    const poolLogicManagerProxy = poolLogicProxy.connect(manager);
    await expect(poolLogicManagerProxy.execTransactions([])).to.be.revertedWith("no transactions to execute");
  });

  it("Should be able to approve", async () => {
    let approveABI = iERC20.encodeFunctionData("approve", [susd, (100e18).toString()]);
    await expect(poolLogicProxy.connect(manager).execTransaction(slink, approveABI)).to.be.revertedWith(
      "asset not enabled in pool",
    );

    await expect(poolLogicProxy.connect(manager).execTransaction(susd, approveABI)).to.be.revertedWith(
      "unsupported spender approval",
    );

    // can't approve unsupported external token to be spent by unsupported external contract
    await expect(
      poolLogicProxy.connect(manager).execTransaction(externalUnsupportedToken, approveABI),
    ).to.be.revertedWith("unsupported spender approval");

    approveABI = iERC20.encodeFunctionData("approve", [uniswapV2Router.address, (100e18).toString()]);

    // can approve unsupported external token to be spent by supported external contract (default ERC20Guard)
    await poolLogicProxy.connect(manager).execTransaction(externalUnsupportedToken, approveABI);

    await susdAsset.givenCalldataReturnBool(approveABI, true);
    await poolLogicProxy.connect(manager).execTransaction(susd, approveABI);
  });

  it("should be able to swap tokens on Uniswap v2", async () => {
    const exchangeEvent = new Promise((resolve, reject) => {
      uniswapV2RouterGuard.once(
        "ExchangeFrom",
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
    const IUniswapV2Router = await hre.artifacts.readArtifact(
      "contracts/interfaces/uniswapV2/IUniswapV2Router.sol:IUniswapV2Router",
    );
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
      BigNumber.from(sourceAmount).mul(95).div(2000).div(100), // Creating a 5% slippage scenario.
      [susd, seth],
      poolLogicProxy.address,
      0,
    ]);
    await assetHandler.setChainlinkTimeout(9000000);

    await expect(poolLogicProxy.connect(manager).execTransaction(uniswapV2Router.address, swapABI)).to.be.revertedWith(
      "slippage impact exceeded",
    );

    swapABI = iUniswapV2Router.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      ethers.BigNumber.from(sourceAmount).mul(99).div(2000).div(100),
      [susd, seth],
      poolLogicProxy.address,
      0,
    ]);
    await poolLogicProxy.connect(manager).execTransaction(uniswapV2Router.address, swapABI);

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const event: any = await exchangeEvent;
    expect(event.sourceAsset).to.equal(susd);
    expect(event.sourceAmount).to.equal((100e18).toString());
    expect(event.destinationAsset).to.equal(seth);
  });

  it.skip("should be able to swap tokens on Uniswap v3 - direct swap", async () => {
    const exchangeEvent = new Promise((resolve, reject) => {
      uniswapV3RouterGuard.once("ExchangeFrom", (pool, sourceAsset, sourceAmount, destinationAsset, time, event) => {
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

    const sourceAmount = (100e18).toString();
    const IUniswapV3Router = await hre.artifacts.readArtifact(
      "contracts/interfaces/uniswapV3/IV3SwapRouter.sol:IV3SwapRouter",
    );
    const iUniswapV3Router = new ethers.utils.Interface(IUniswapV3Router.abi);
    const exactInputSingleParams = {
      tokenIn: susd,
      tokenOut: seth,
      fee: 10000,
      recipient: poolManagerLogicProxy.address,
      amountIn: sourceAmount,
      amountOutMinimum: 0,
      sqrtPriceLimitX96: 0,
    };
    const badExactInputSingleParams = exactInputSingleParams;

    // fail to swap direct asset to asset because it is interaction is with 0x0 address
    let swapABI = iUniswapV3Router.encodeFunctionData("exactInputSingle", [exactInputSingleParams]);
    await expect(poolLogicProxy.connect(manager).execTransaction(ZERO_ADDRESS, swapABI)).to.be.revertedWith(
      "non-zero address is required",
    );

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

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const event: any = await exchangeEvent;
    expect(event.sourceAsset).to.equal(susd);
    expect(event.sourceAmount).to.equal(sourceAmount);
    expect(event.destinationAsset).to.equal(seth);
  });

  it.skip("should be able to swap tokens on Uniswap v3 - multi swap", async () => {
    const exchangeEvent = new Promise((resolve, reject) => {
      uniswapV3RouterGuard.once("ExchangeFrom", (pool, sourceAsset, sourceAmount, destinationAsset, time, event) => {
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

    const sourceAmount = (100e18).toString();
    const IUniswapV3Router = await hre.artifacts.readArtifact(
      "contracts/interfaces/uniswapV3/IV3SwapRouter.sol:IV3SwapRouter",
    );
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
      amountIn: sourceAmount,
      amountOutMinimum: 0,
    };
    const badExactInputParams = exactInputParams;

    // fail to swap direct asset to asset because it is interaction is with 0x0 address
    let swapABI = iUniswapV3Router.encodeFunctionData("exactInput", [exactInputParams]);
    await expect(poolLogicProxy.connect(manager).execTransaction(ZERO_ADDRESS, swapABI)).to.be.revertedWith(
      "non-zero address is required",
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

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const event: any = await exchangeEvent;
    expect(event.sourceAsset).to.equal(susd);
    expect(event.sourceAmount).to.equal(sourceAmount);
    expect(event.destinationAsset).to.equal(seth);
  });

  it("Fails to execute 1inch swap exchange because bad destination asset", async () => {
    const exchangeCallData =
      "0x7c025200000000000000000000000000db38ae75c5f44276803345f7f02e95a0aeef5944000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000001800000000000000000000000001494ca1f11d487c2bbe4543e90080aeba4ba3c2b0000000000000000000000006b175474e89094c44da98b954eedeac495271d0f000000000000000000000000db38ae75c5f44276803345f7f02e95a0aeef5944000000000000000000000000ece772fe6bb5e9869c12ecfa94f5a6b463ee6cd7000000000000000000000000000000000000000000000003e54b148587a6ce490000000000000000000000000000000000000000000006c20362d119aa7f38d30000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000d800000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000500000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000001c000000000000000000000000000000000000000000000000000000000000005a000000000000000000000000000000000000000000000000000000000000008c00000000000000000000000000000000000000000000000000000000000000b0080000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000064eb5625d90000000000000000000000001494ca1f11d487c2bbe4543e90080aeba4ba3c2b00000000000000000000000095e6f48254609a6ee006f7d493c8e5fb97094cef000000000000000000000000000000000000000000000003e54b148587a6ce4900000000000000000000000000000000000000000000000000000000800000000000000000000000080bf510fcbf18b91105470639e95610229377120000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000324b4be83d50000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000003e54b148587a6ce4900000000000000000000000000000000000000000000000000000000000002a000000000000000000000000056178a0d5f301baf6cf3e1cd53d9863437345bf9000000000000000000000000db38ae75c5f44276803345f7f02e95a0aeef594400000000000000000000000055662e225a3376759c24331a9aed764f8f0c9fbb00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006f6f97a866956390000000000000000000000000000000000000000000000000003e54b3df4a3fc80000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000607be3af0000000000000000000000000000000000000000000000001676e3f39095d48e000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000001e00000000000000000000000000000000000000000000000000000000000000024f47261b00000000000000000000000006b175474e89094c44da98b954eedeac495271d0f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000024f47261b00000000000000000000000001494ca1f11d487c2bbe4543e90080aeba4ba3c2b0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000421c5d04f70eb228dcc5e5c1b17c8c7d75cd62f271c09116dae9c93e2d20338b7fba22544c50513642874d6dc0fef510361ca49625ca57f635a7f361ff77c67d17e00300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000002647f8fe7a000000000000000000000000000000000000000000000000000000000000000808000000000000000000000000000000000000000000000000000000000000044000000000000000000000000db38ae75c5f44276803345f7f02e95a0aeef594400000000000000000000000000000000000000000000000000000000000001e0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000a4059712240000000000000000000000006b175474e89094c44da98b954eedeac495271d0f0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000001000000000000000000000000000000010000000000000000000000000000000000000000000000006ecf6b9dd76b128800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004470bdb9470000000000000000000000006b175474e89094c44da98b954eedeac495271d0f0000000000000000000000000000000000000000000006f784cf70a3b268c3d2000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000184b3af37c00000000000000000000000000000000000000000000000000000000000000080a0000000000000000000000000000000000000000000000000000000000000240000000000000000000000001494ca1f11d487c2bbe4543e90080aeba4ba3c2b00000000000000000000000000000001000000000000000000000000000000010000000000000000000000001494ca1f11d487c2bbe4543e90080aeba4ba3c2b0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000044a9059cbb000000000000000000000000910bf2d50fa5e014fd06666f456182d4ab7c8bd20000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000184b3af37c0000000000000000000000000000000000000000000000000000000000000008080000000000000000000000000000000000000000000000000000000000000240000000000000000000000006b175474e89094c44da98b954eedeac495271d0f00000000000000000000000000000001000000000000000000000000000000010000000000000000000000006b175474e89094c44da98b954eedeac495271d0f0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000044a9059cbb000000000000000000000000ece772fe6bb5e9869c12ecfa94f5a6b463ee6cd700000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

    await expect(
      poolLogicProxy.connect(manager).execTransaction(oneInchRouter.address, exchangeCallData),
    ).to.be.revertedWith("unsupported destination asset");
  });

  it("Fails to execute 1inch swap exchange because bad destination asset", async () => {
    const exchangeCallData =
      "0x7c025200000000000000000000000000db38ae75c5f44276803345f7f02e95a0aeef5944000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000001800000000000000000000000001494ca1f11d487c2bbe4543e90080aeba4ba3c2b0000000000000000000000006b175474e89094c44da98b954eedeac495271d0f000000000000000000000000db38ae75c5f44276803345f7f02e95a0aeef5944000000000000000000000000ece772fe6bb5e9869c12ecfa94f5a6b463ee6cd7000000000000000000000000000000000000000000000003e54b148587a6ce490000000000000000000000000000000000000000000006c20362d119aa7f38d30000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000d800000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000500000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000001c000000000000000000000000000000000000000000000000000000000000005a000000000000000000000000000000000000000000000000000000000000008c00000000000000000000000000000000000000000000000000000000000000b0080000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000064eb5625d90000000000000000000000001494ca1f11d487c2bbe4543e90080aeba4ba3c2b00000000000000000000000095e6f48254609a6ee006f7d493c8e5fb97094cef000000000000000000000000000000000000000000000003e54b148587a6ce4900000000000000000000000000000000000000000000000000000000800000000000000000000000080bf510fcbf18b91105470639e95610229377120000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000324b4be83d50000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000003e54b148587a6ce4900000000000000000000000000000000000000000000000000000000000002a000000000000000000000000056178a0d5f301baf6cf3e1cd53d9863437345bf9000000000000000000000000db38ae75c5f44276803345f7f02e95a0aeef594400000000000000000000000055662e225a3376759c24331a9aed764f8f0c9fbb00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006f6f97a866956390000000000000000000000000000000000000000000000000003e54b3df4a3fc80000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000607be3af0000000000000000000000000000000000000000000000001676e3f39095d48e000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000001e00000000000000000000000000000000000000000000000000000000000000024f47261b00000000000000000000000006b175474e89094c44da98b954eedeac495271d0f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000024f47261b00000000000000000000000001494ca1f11d487c2bbe4543e90080aeba4ba3c2b0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000421c5d04f70eb228dcc5e5c1b17c8c7d75cd62f271c09116dae9c93e2d20338b7fba22544c50513642874d6dc0fef510361ca49625ca57f635a7f361ff77c67d17e00300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000002647f8fe7a000000000000000000000000000000000000000000000000000000000000000808000000000000000000000000000000000000000000000000000000000000044000000000000000000000000db38ae75c5f44276803345f7f02e95a0aeef594400000000000000000000000000000000000000000000000000000000000001e0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000a4059712240000000000000000000000006b175474e89094c44da98b954eedeac495271d0f0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000001000000000000000000000000000000010000000000000000000000000000000000000000000000006ecf6b9dd76b128800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004470bdb9470000000000000000000000006b175474e89094c44da98b954eedeac495271d0f0000000000000000000000000000000000000000000006f784cf70a3b268c3d2000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000184b3af37c00000000000000000000000000000000000000000000000000000000000000080a0000000000000000000000000000000000000000000000000000000000000240000000000000000000000001494ca1f11d487c2bbe4543e90080aeba4ba3c2b00000000000000000000000000000001000000000000000000000000000000010000000000000000000000001494ca1f11d487c2bbe4543e90080aeba4ba3c2b0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000044a9059cbb000000000000000000000000910bf2d50fa5e014fd06666f456182d4ab7c8bd20000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000184b3af37c0000000000000000000000000000000000000000000000000000000000000008080000000000000000000000000000000000000000000000000000000000000240000000000000000000000006b175474e89094c44da98b954eedeac495271d0f00000000000000000000000000000001000000000000000000000000000000010000000000000000000000006b175474e89094c44da98b954eedeac495271d0f0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000044a9059cbb000000000000000000000000ece772fe6bb5e9869c12ecfa94f5a6b463ee6cd700000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

    await expect(
      poolLogicProxy.connect(manager).execTransaction(oneInchRouter.address, exchangeCallData),
    ).to.be.revertedWith("unsupported destination asset");
  });

  it("Fails to execute 1inch swap exchange because bad recipient", async () => {
    const exchangeCallData =
      "0x7c02520000000000000000000000000027239549dd40e1d60f5b80b0c4196923745b1fd200000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000180000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee000000000000000000000000" +
      slink.toLowerCase().slice(2, slink.length) +
      "00000000000000000000000027239549dd40e1d60f5b80b0c4196923745b1fd200000000000000000000000052bc44d5378309ee2abf1539bf71de1b7d7be3b50000000000000000000000000000000000000000000000056bc75e2d631000000000000000000000000000000000000000000000000044073670020b6564a6000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000c00000000000000000000000000000000000000000000000000000000000000180000000000000000000000000000000000000000000000000000000000000034000000000000000000000000000000000000000000000000000000000000005a0000000000000000000000000000000000000000000000000000000000000068000000000000000000000000000000000000000000000000000000000000009a0000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000056bc75e2d6310000000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000004d0e30db00000000000000000000000000000000000000000000000000000000080000000000000000000000011b815efb8f581194ae79006d24e0d814b7697f60000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000104128acb0800000000000000000000000027239549dd40e1d60f5b80b0c4196923745b1fd200000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000056bc75e2d6310000000000000000000000000000000000000000000000000000000000001000276a400000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000040000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec700000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000001a4b3af37c000000000000000000000000000000000000000000000000000000000000000808000000000000000000000000000000000000000000000000000000000000044000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec7000000000000000000000000000000320000000000000000000000000000003200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000064d1660f99000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec70000000000000000000000003058ef90929cb8180174d74c507176cca6835d73000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000000000003058ef90929cb8180174d74c507176cca6835d730000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000024dd93f59a00000000000000000000000027239549dd40e1d60f5b80b0c4196923745b1fd200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000002647f8fe7a00000000000000000000000000000000000000000000000000000000000000080800000000000000000000000000000000000000000000000000000000000004400000000000000000000000027239549dd40e1d60f5b80b0c4196923745b1fd200000000000000000000000000000000000000000000000000000000000001e0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000a4059712240000000000000000000000006b175474e89094c44da98b954eedeac495271d0f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000100000000000000000000000000000001000000000000000000000000000000000000000000000000454e93cbdf7dccc000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004470bdb9470000000000000000000000006b175474e89094c44da98b954eedeac495271d0f0000000000000000000000000000000000000000000044b71fb6f522c8ae11b3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000184b3af37c0000000000000000000000000000000000000000000000000000000000000008080000000000000000000000000000000000000000000000000000000000000240000000000000000000000006b175474e89094c44da98b954eedeac495271d0f00000000000000000000000000000001000000000000000000000000000000010000000000000000000000006b175474e89094c44da98b954eedeac495271d0f0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000044a9059cbb00000000000000000000000052bc44d5378309ee2abf1539bf71de1b7d7be3b500000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

    await poolManagerLogicProxy.connect(manager).changeAssets(
      [
        {
          asset: slink,
          isDeposit: false,
        },
      ],
      [],
    );
    await expect(
      poolLogicProxy.connect(manager).execTransaction(oneInchRouter.address, exchangeCallData),
    ).to.be.revertedWith("recipient is not pool");
  });

  it("Should execute 1inch swap exchange", async () => {
    const poolAddress = poolLogicProxy.address;
    const exchangeCallData =
      "0x7c02520000000000000000000000000027239549dd40e1d60f5b80b0c4196923745b1fd200000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000180000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee000000000000000000000000" +
      slink.toLowerCase().slice(2, slink.length) +
      "00000000000000000000000027239549dd40e1d60f5b80b0c4196923745b1fd2000000000000000000000000" +
      poolAddress.toLowerCase().slice(2, poolAddress.length) +
      "0000000000000000000000000000000000000000000000056bc75e2d631000000000000000000000000000000000000000000000000044073670020b6564a6000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000c00000000000000000000000000000000000000000000000000000000000000180000000000000000000000000000000000000000000000000000000000000034000000000000000000000000000000000000000000000000000000000000005a0000000000000000000000000000000000000000000000000000000000000068000000000000000000000000000000000000000000000000000000000000009a0000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000056bc75e2d6310000000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000004d0e30db00000000000000000000000000000000000000000000000000000000080000000000000000000000011b815efb8f581194ae79006d24e0d814b7697f60000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000104128acb0800000000000000000000000027239549dd40e1d60f5b80b0c4196923745b1fd200000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000056bc75e2d6310000000000000000000000000000000000000000000000000000000000001000276a400000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000040000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec700000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000001a4b3af37c000000000000000000000000000000000000000000000000000000000000000808000000000000000000000000000000000000000000000000000000000000044000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec7000000000000000000000000000000320000000000000000000000000000003200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000064d1660f99000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec70000000000000000000000003058ef90929cb8180174d74c507176cca6835d73000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000000000003058ef90929cb8180174d74c507176cca6835d730000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000024dd93f59a00000000000000000000000027239549dd40e1d60f5b80b0c4196923745b1fd200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000002647f8fe7a00000000000000000000000000000000000000000000000000000000000000080800000000000000000000000000000000000000000000000000000000000004400000000000000000000000027239549dd40e1d60f5b80b0c4196923745b1fd200000000000000000000000000000000000000000000000000000000000001e0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000a4059712240000000000000000000000006b175474e89094c44da98b954eedeac495271d0f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000100000000000000000000000000000001000000000000000000000000000000000000000000000000454e93cbdf7dccc000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004470bdb9470000000000000000000000006b175474e89094c44da98b954eedeac495271d0f0000000000000000000000000000000000000000000044b71fb6f522c8ae11b3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000184b3af37c0000000000000000000000000000000000000000000000000000000000000008080000000000000000000000000000000000000000000000000000000000000240000000000000000000000006b175474e89094c44da98b954eedeac495271d0f00000000000000000000000000000001000000000000000000000000000000010000000000000000000000006b175474e89094c44da98b954eedeac495271d0f0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000044a9059cbb00000000000000000000000052bc44d5378309ee2abf1539bf71de1b7d7be3b500000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

    await oneInchRouter.givenCalldataReturn(
      exchangeCallData,
      abiCoder.encode(["uint256", "uint256", "uint256"], [0, 0, 0]),
    );
    await poolLogicProxy.connect(manager).execTransaction(oneInchRouter.address, exchangeCallData);
  });

  it("should be able to mint manager fee", async () => {
    await poolFactory.setDaoFee(10, 100);
    const daoFees = await poolFactory.getDaoFee();
    expect(daoFees[0]).to.be.equal(10);
    expect(daoFees[1]).to.be.equal(100);

    await assetHandler.setChainlinkTimeout(9000000);

    await ethers.provider.send("evm_increaseTime", [3600 * 24]);
    await ethers.provider.send("evm_mine", []);

    const daoBalanceBefore = BigNumber.from(await poolLogicProxy.balanceOf(dao.address));
    const tokenPriceAtLastFeeMint = await poolLogicProxy.tokenPriceAtLastFeeMint();
    const availableFeePreMint = await poolLogicProxy.availableManagerFee();
    const tokenPricePreMint = await poolLogicProxy.tokenPriceWithoutManagerFee();
    const totalSupplyPreMint = await poolLogicProxy.totalSupply();
    // const performanceFeeNumerator = await poolManagerLogicProxy.performanceFeeNumerator();
    const managerFeeNumerator = await poolManagerLogicProxy.managerFeeNumerator();
    expect(tokenPriceAtLastFeeMint).gte(tokenPricePreMint);
    const calculatedAvailableFee = totalSupplyPreMint
      .mul(BigNumber.from(await currentBlockTimestamp()).sub(await poolLogicProxy.lastFeeMintTime()))
      .mul(managerFeeNumerator)
      .div(10000)
      .div(86400 * 365);

    expect(availableFeePreMint).to.be.gt("0"); // the test needs to have some available fee to claim

    expect(availableFeePreMint).to.equal(calculatedAvailableFee);

    await poolLogicProxy.mintManagerFee();

    const tokenPricePostMint = await poolLogicProxy.tokenPrice();
    const totalSupplyPostMint = await poolLogicProxy.totalSupply();
    const expectedTotalSupplyPostMint = totalSupplyPreMint.add(availableFeePreMint);
    const expectedTokenPricePostMint = tokenPricePreMint.mul(totalSupplyPreMint).div(totalSupplyPostMint);
    const expectedDAOBalance = daoBalanceBefore.add(availableFeePreMint.mul(daoFees[0]).div(daoFees[1]));

    expect(totalSupplyPostMint).to.be.closeTo(expectedTotalSupplyPostMint, expectedTotalSupplyPostMint.div(10_000));
    expect(tokenPricePostMint).to.be.closeTo(expectedTokenPricePostMint, expectedTokenPricePostMint.div(10_000));
    expect(await poolLogicProxy.balanceOf(dao.address)).to.be.closeTo(
      expectedDAOBalance,
      expectedDAOBalance.div(10_000),
    );

    const availableFeePostMint = await poolLogicProxy.availableManagerFee();
    expect(availableFeePostMint).to.be.eq("0");

    await assetHandler.setChainlinkTimeout(90000);
  });

  it("should be able to pause deposit, exchange/execute and withdraw", async function () {
    const poolLogicManagerProxy = poolLogicProxy.connect(manager);

    await expect(poolFactory.connect(manager).pause()).to.be.revertedWith("caller is not the owner");
    await poolFactory.pause();
    expect(await poolFactory.isPaused()).to.be.true;

    await expect(
      poolFactory.createFund(false, manager.address, "Barren Wuffet", "Test Fund", "DHTF", "6000", "200", [
        {
          asset: susd,
          isDeposit: true,
        },
        {
          asset: seth,
          isDeposit: true,
        },
      ]),
    ).to.be.revertedWith("contracts paused");

    await expect(poolLogicProxy.deposit(susd, (100e18).toString())).to.be.revertedWith("contracts paused");
    await expect(poolLogicProxy.withdraw((100e18).toString())).to.be.revertedWith("contracts paused");
    await expect(poolLogicManagerProxy.execTransaction(synthetix.address, "0x00")).to.be.revertedWith(
      "contracts paused",
    );

    await expect(poolFactory.connect(manager).unpause()).to.be.revertedWith("caller is not the owner");
    await poolFactory.unpause();
    expect(await poolFactory.isPaused()).to.be.false;

    await expect(poolLogicProxy.deposit(susd, (100e18).toString())).to.not.be.revertedWith("contracts paused");
    await expect(poolLogicProxy.withdraw((100e18).toString())).to.not.be.revertedWith("contracts paused");
    await expect(poolLogicManagerProxy.execTransaction(synthetix.address, "0x00")).to.not.be.revertedWith(
      "contracts paused",
    );
  });

  describe("AssetHandler", function () {
    it("only owner should be able to remove assets", async function () {
      expect(await assetHandler.assetTypes(susd)).to.be.equal(1);
      expect(await assetHandler.assetTypes(seth)).to.be.equal(1);
      expect(await assetHandler.assetTypes(slink)).to.be.equal(1);
      expect(await assetHandler.assetTypes(ZERO_ADDRESS)).to.be.equal(0);
      expect(await assetHandler.priceAggregators(susd)).to.be.equal(usd_price_feed.address);
      expect(await assetHandler.priceAggregators(seth)).to.be.equal(eth_price_feed.address);
      expect(await assetHandler.priceAggregators(slink)).to.be.equal(link_price_feed.address);
      expect(await assetHandler.priceAggregators(ZERO_ADDRESS)).to.be.equal(ZERO_ADDRESS);

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
      const current = (await ethers.provider.getBlock(await ethers.provider.getBlockNumber())).timestamp;
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

    it("only manager can call setNftMembershipCollectionAddress", async () => {
      await expect(poolManagerLogicProxy.setNftMembershipCollectionAddress(logicOwner.address)).to.be.revertedWith(
        "only manager",
      );
    });

    it("should be able to add and remove nft collection", async () => {
      const MockContract = await ethers.getContractFactory("MockContract");
      const nftCollectionMock = await MockContract.deploy();
      await poolManagerLogicProxy.connect(manager).setNftMembershipCollectionAddress(nftCollectionMock.address);
      await poolManagerLogicProxy.connect(manager).setNftMembershipCollectionAddress(ZERO_ADDRESS);
      expect(await poolManagerLogicProxy.nftMembershipCollectionAddress()).to.equal(ZERO_ADDRESS);
    });

    it("should not be able to set nft collection to contract without balanceOf func", async () => {
      expect(
        poolManagerLogicProxy.connect(manager).setNftMembershipCollectionAddress(poolFactory.address),
      ).to.be.revertedWith("Invalid collection");
    });

    it("should be able to have members that must own nft", async () => {
      const MockContract = await ethers.getContractFactory("MockContract");
      const nftCollectionMock = await MockContract.deploy();
      await poolManagerLogicProxy.connect(manager).setNftMembershipCollectionAddress(nftCollectionMock.address);
      // We only use balanceOf and IERC20 has same balanceof as erc721
      const nftAbi = new ethers.utils.Interface(IERC20__factory.abi);
      const balanceOfABI = nftAbi.encodeFunctionData("balanceOf", [user3.address]);
      await nftCollectionMock.givenCalldataReturnUint(balanceOfABI, (1).toString());

      expect(await poolManagerLogicProxy.isMemberAllowed(user3.address)).to.be.true;
    });

    it("should return false for member that doesn't own nft", async () => {
      const MockContract = await ethers.getContractFactory("MockContract");
      const nftCollectionMock = await MockContract.deploy();
      await poolManagerLogicProxy.connect(manager).setNftMembershipCollectionAddress(nftCollectionMock.address);
      // We only use balanceOf and IERC20 has same balanceof as erc721
      const nftAbi = new ethers.utils.Interface(IERC20__factory.abi);
      const balanceOfABI = nftAbi.encodeFunctionData("balanceOf", [user3.address]);
      await nftCollectionMock.givenCalldataReturnUint(balanceOfABI, 0);

      expect(await poolManagerLogicProxy.isMemberAllowed(user3.address)).to.be.false;
    });
  });

  it("can set Sushi pool ID", async () => {
    expect(sushiLPAssetGuard.setSushiPoolId(ZERO_ADDRESS, "1")).to.be.revertedWith("Invalid lpToken address");

    const contract = "0x1111111111111111111111111111111111111111";
    await sushiLPAssetGuard.setSushiPoolId(contract, "1");
    const poolId = await sushiLPAssetGuard.sushiPoolIds(contract);
    expect(poolId).to.be.equal("1");
  });

  describe("Staking", function () {
    it("manager can Stake Sushi LP token", async function () {
      const stakeEvent = new Promise((resolve, reject) => {
        sushiMiniChefV2Guard.once("Stake", (fundAddress, asset, stakingContract, amount, time, event) => {
          event.removeListener();

          resolve({
            fundAddress,
            asset,
            stakingContract,
            amount,
            time,
          });
        });

        setTimeout(() => {
          reject(new Error("timeout"));
        }, 60000);
      });

      // refresh timestamp of Chainlink price round data
      await updateChainlinkAggregators(usd_price_feed, eth_price_feed, link_price_feed);

      const depositAbi = iMiniChefV2.encodeFunctionData("deposit", [
        sushiLPLinkWethPoolId,
        FIVE_TOKENS,
        poolLogicProxy.address,
      ]);

      await expect(
        poolLogicProxy.connect(manager).execTransaction(sushiMiniChefV2.address, depositAbi),
      ).to.be.revertedWith("unsupported lp asset");

      // enable Sushi LP token to pool
      await poolManagerLogicProxy.connect(manager).changeAssets(
        [
          {
            asset: sushiLPLinkWeth,
            isDeposit: false,
          },
        ],
        [],
      );

      // mock 5 Sushi LP tokens in pool
      const balanceOfABI = iERC20.encodeFunctionData("balanceOf", [poolLogicProxy.address]);
      await sushiLPLinkWethAsset.givenCalldataReturnUint(balanceOfABI, FIVE_TOKENS);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      const sushiLPPrice = await assetHandler.getUSDPrice(sushiLPLinkWeth);
      expect(totalFundValueBefore).to.gte(sushiLPPrice.mul(5)); // should at least account for the staked tokens

      // attempt to deposit with manager as recipient
      const badDepositAbi = iMiniChefV2.encodeFunctionData("deposit", [
        sushiLPLinkWethPoolId,
        FIVE_TOKENS,
        manager.address,
      ]);

      await expect(
        poolLogicProxy.connect(manager).execTransaction(sushiMiniChefV2.address, badDepositAbi),
      ).to.be.revertedWith("recipient is not pool");

      await expect(
        poolLogicProxy.connect(manager).execTransaction(sushiMiniChefV2.address, depositAbi),
      ).to.be.revertedWith("enable reward token");

      // enable SUSHI token in pool
      await poolManagerLogicProxy.connect(manager).changeAssets(
        [
          {
            asset: sushiToken.address,
            isDeposit: false,
          },
        ],
        [],
      );

      await expect(
        poolLogicProxy.connect(manager).execTransaction(sushiMiniChefV2.address, depositAbi),
      ).to.be.revertedWith("enable reward token");

      // enable WMATIC token in pool
      await poolManagerLogicProxy.connect(manager).changeAssets(
        [
          {
            asset: wmaticToken.address,
            isDeposit: false,
          },
        ],
        [],
      );

      await poolLogicProxy.connect(manager).execTransaction(sushiMiniChefV2.address, depositAbi);

      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const event: any = await stakeEvent;
      expect(event.fundAddress).to.equal(poolLogicProxy.address);
      expect(event.asset).to.equal(sushiLPLinkWeth);
      expect(event.stakingContract).to.equal(sushiMiniChefV2.address);
      expect(event.amount).to.equal(FIVE_TOKENS);
      expect(event.time).to.equal((await currentBlockTimestamp()).toString());
    });

    it("manager can Unstake Sushi LP token", async function () {
      const unstakeEvent = new Promise((resolve, reject) => {
        sushiMiniChefV2Guard.once("Unstake", (fundAddress, asset, stakingContract, amount, time, event) => {
          event.removeListener();

          resolve({
            fundAddress,
            asset,
            stakingContract,
            amount,
            time,
          });
        });

        setTimeout(() => {
          reject(new Error("timeout"));
        }, 60000);
      });

      // attempt to withdraw with manager as recipient
      const badWithdrawAbi = iMiniChefV2.encodeFunctionData("withdraw", [
        sushiLPLinkWethPoolId,
        FIVE_TOKENS,
        manager.address,
      ]);

      await expect(
        poolLogicProxy.connect(manager).execTransaction(sushiMiniChefV2.address, badWithdrawAbi),
      ).to.be.revertedWith("recipient is not pool");

      const withdrawAbi = iMiniChefV2.encodeFunctionData("withdraw", [
        sushiLPLinkWethPoolId,
        FIVE_TOKENS,
        poolLogicProxy.address,
      ]);

      await poolLogicProxy.connect(manager).execTransaction(sushiMiniChefV2.address, withdrawAbi);

      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const event: any = await unstakeEvent;
      expect(event.fundAddress).to.equal(poolLogicProxy.address);
      expect(event.asset).to.equal(sushiLPLinkWeth);
      expect(event.stakingContract).to.equal(sushiMiniChefV2.address);
      expect(event.amount).to.equal(FIVE_TOKENS);
      expect(event.time).to.equal((await currentBlockTimestamp()).toString());
    });

    it("manager can Harvest staked Sushi LP token", async function () {
      const claimEvent = new Promise((resolve, reject) => {
        sushiMiniChefV2Guard.once("Claim", (fundAddress, stakingContract, time, event) => {
          event.removeListener();

          resolve({
            fundAddress,
            stakingContract,
            time,
          });
        });

        setTimeout(() => {
          reject(new Error("timeout"));
        }, 60000);
      });

      const harvestAbi = iMiniChefV2.encodeFunctionData("harvest", [sushiLPLinkWethPoolId, poolLogicProxy.address]);

      // attempt to harvest with manager as recipient
      const badHarvestAbi = iMiniChefV2.encodeFunctionData("withdraw", [
        sushiLPLinkWethPoolId,
        FIVE_TOKENS,
        manager.address,
      ]);

      await expect(
        poolLogicProxy.connect(manager).execTransaction(sushiMiniChefV2.address, badHarvestAbi),
      ).to.be.revertedWith("recipient is not pool");

      await poolLogicProxy.connect(manager).execTransaction(sushiMiniChefV2.address, harvestAbi);

      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const event: any = await claimEvent;
      expect(event.fundAddress).to.equal(poolLogicProxy.address);
      expect(event.stakingContract).to.equal(sushiMiniChefV2.address);
      expect(event.time).to.equal((await currentBlockTimestamp()).toString());
    });

    it("user can Harvest staked Sushi LP token", async function () {
      const claimEvent = new Promise((resolve, reject) => {
        sushiMiniChefV2Guard.once("Claim", (fundAddress, stakingContract, time, event) => {
          event.removeListener();

          resolve({
            fundAddress,
            stakingContract,
            time,
          });
        });

        setTimeout(() => {
          reject(new Error("timeout"));
        }, 60000);
      });

      const harvestAbi = iMiniChefV2.encodeFunctionData("harvest", [sushiLPLinkWethPoolId, poolLogicProxy.address]);

      // attempt to harvest with manager as recipient
      const badHarvestAbi = iMiniChefV2.encodeFunctionData("withdraw", [
        sushiLPLinkWethPoolId,
        FIVE_TOKENS,
        manager.address,
      ]);

      await expect(
        poolLogicProxy.connect(logicOwner).execTransaction(sushiMiniChefV2.address, badHarvestAbi),
      ).to.be.revertedWith("recipient is not pool");

      await poolLogicProxy.connect(logicOwner).execTransaction(sushiMiniChefV2.address, harvestAbi);

      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const event: any = await claimEvent;
      expect(event.fundAddress).to.equal(poolLogicProxy.address);
      expect(event.stakingContract).to.equal(sushiMiniChefV2.address);
      expect(parseInt(event.time)).to.be.lessThanOrEqual(await currentBlockTimestamp());
    });

    it("manager can Withdraw And Harvest staked Sushi LP token", async function () {
      const unstakeEvent = new Promise((resolve, reject) => {
        sushiMiniChefV2Guard.once("Unstake", (fundAddress, asset, stakingContract, amount, time, event) => {
          event.removeListener();

          resolve({
            fundAddress,
            asset,
            stakingContract,
            amount,
            time,
          });
        });

        setTimeout(() => {
          reject(new Error("timeout"));
        }, 60000);
      });

      const claimEvent = new Promise((resolve, reject) => {
        sushiMiniChefV2Guard.once("Claim", (fundAddress, stakingContract, time, event) => {
          event.removeListener();

          resolve({
            fundAddress,
            stakingContract,
            time,
          });
        });

        setTimeout(() => {
          reject(new Error("timeout"));
        }, 60000);
      });

      // manager attempts to withdraw to themselves
      let badWithdrawAndHarvestAbi = iMiniChefV2.encodeFunctionData("withdrawAndHarvest", [
        sushiLPLinkWethPoolId,
        FIVE_TOKENS,
        manager.address,
      ]);

      await expect(
        poolLogicProxy.connect(manager).execTransaction(sushiMiniChefV2.address, badWithdrawAndHarvestAbi),
      ).to.be.revertedWith("recipient is not pool");

      // manager attempts to withdraw unknown LP token
      badWithdrawAndHarvestAbi = iMiniChefV2.encodeFunctionData("withdrawAndHarvest", [
        "69",
        FIVE_TOKENS,
        poolLogicProxy.address,
      ]);

      await expect(
        poolLogicProxy.connect(manager).execTransaction(sushiMiniChefV2.address, badWithdrawAndHarvestAbi),
      ).to.be.revertedWith("unsupported lp asset");

      const withdrawAndHarvestAbi = iMiniChefV2.encodeFunctionData("withdrawAndHarvest", [
        sushiLPLinkWethPoolId,
        FIVE_TOKENS,
        poolLogicProxy.address,
      ]);

      // Disable SUSHI token in pool
      await poolManagerLogicProxy.connect(manager).changeAssets([], [sushiToken.address]);

      // Disable WMATIC token in pool
      await poolManagerLogicProxy.connect(manager).changeAssets([], [wmaticToken.address]);

      await expect(
        poolLogicProxy.connect(manager).execTransaction(sushiMiniChefV2.address, withdrawAndHarvestAbi),
      ).to.be.revertedWith("enable reward token");

      // enable SUSHI token in pool
      await poolManagerLogicProxy.connect(manager).changeAssets(
        [
          {
            asset: sushiToken.address,
            isDeposit: false,
          },
        ],
        [],
      );

      await expect(
        poolLogicProxy.connect(manager).execTransaction(sushiMiniChefV2.address, withdrawAndHarvestAbi),
      ).to.be.revertedWith("enable reward token");

      // enable WMATIC token in pool
      await poolManagerLogicProxy.connect(manager).changeAssets(
        [
          {
            asset: wmaticToken.address,
            isDeposit: false,
          },
        ],
        [],
      );

      await poolLogicProxy.connect(manager).execTransaction(sushiMiniChefV2.address, withdrawAndHarvestAbi);

      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const eventUnstake: any = await unstakeEvent;
      expect(eventUnstake.fundAddress).to.equal(poolLogicProxy.address);
      expect(eventUnstake.asset).to.equal(sushiLPLinkWeth);
      expect(eventUnstake.stakingContract).to.equal(sushiMiniChefV2.address);
      expect(eventUnstake.amount).to.equal(FIVE_TOKENS);
      expect(parseInt(eventUnstake.time)).to.be.lessThanOrEqual(await currentBlockTimestamp());

      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const eventClaim: any = await claimEvent;
      expect(eventClaim.fundAddress).to.equal(poolLogicProxy.address);
      expect(eventClaim.stakingContract).to.equal(sushiMiniChefV2.address);
      expect(parseInt(eventClaim.time)).to.be.lessThanOrEqual(await currentBlockTimestamp());
    });

    it("investor can Withdraw staked Sushi LP token", async function () {
      const withdrawalEvent = new Promise((resolve, reject) => {
        poolLogicProxy.once(
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

      // refresh timestamp of Chainlink price round data
      await updateChainlinkAggregators(usd_price_feed, eth_price_feed, link_price_feed);

      // enable Sushi LP token to pool
      await poolManagerLogicProxy.connect(manager).changeAssets(
        [
          {
            asset: sushiLPLinkWeth,
            isDeposit: false,
          },
        ],
        [],
      );

      // remove manager fee so that performance fee minting doesn't get in the way
      await poolManagerLogicProxy.connect(manager).setFeeNumerator("0", "0", "0");

      // mock 20 sUSD in pool
      const balanceOfABI = iERC20.encodeFunctionData("balanceOf", [poolLogicProxy.address]);
      await susdProxy.givenCalldataReturnUint(balanceOfABI, TWENTY_TOKENS);

      // mock 5 Sushi LP tokens in pool
      await sushiLPLinkWethAsset.givenCalldataReturnUint(balanceOfABI, FIVE_TOKENS);

      // mock 100 Sushi LP tokens staked in MiniChefV2
      const userInfo = iMiniChefV2.encodeFunctionData("userInfo", [sushiLPLinkWethPoolId, poolLogicProxy.address]);
      const amountLPStaked = BigNumber.from(ONE_HUNDRED_TOKENS);
      const amountRewarded = (0).toString();
      await sushiMiniChefV2.givenCalldataReturn(
        userInfo,
        abiCoder.encode(["uint256", "uint256"], [amountLPStaked, amountRewarded]),
      );

      const totalSupply = await poolLogicProxy.totalSupply();
      const totalFundValue = await poolManagerLogicProxy.totalFundValue();
      const sushiLPPrice = await assetHandler.getUSDPrice(sushiLPLinkWeth);
      const fundUsdValue = BigNumber.from(TWENTY_TOKENS);
      const fundSushiLPValue = sushiLPPrice.mul(5);
      const stakedSushiLPValue = sushiLPPrice.mul(100);
      const expectedFundValue = fundUsdValue.add(fundSushiLPValue).add(stakedSushiLPValue);
      expect(totalFundValue).to.equal(expectedFundValue);

      // Withdraw 10 tokens
      const withdrawAmount = BigNumber.from(TEN_TOKENS);
      const investorFundBalance = await poolLogicProxy.balanceOf(investor.address);

      await ethers.provider.send("evm_increaseTime", [3600 * 24]); // add 1 day to avoid cooldown revert
      await poolLogicProxy.connect(investor).withdraw(withdrawAmount);

      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const eventWithdrawal: any = await withdrawalEvent;

      const valueWithdrawn = withdrawAmount.mul(totalFundValue).div(totalSupply);
      const expectedFundValueAfter = totalFundValue.sub(valueWithdrawn);

      expect(eventWithdrawal.fundAddress).to.equal(poolLogicProxy.address);
      expect(eventWithdrawal.investor).to.equal(investor.address);
      expect(eventWithdrawal.valueWithdrawn).to.be.closeTo(valueWithdrawn, valueWithdrawn.div(1000));
      expect(eventWithdrawal.fundTokensWithdrawn).to.equal(withdrawAmount.toString());
      expect(eventWithdrawal.totalInvestorFundTokens).to.be.closeTo(
        investorFundBalance.sub(withdrawAmount),
        investorFundBalance.sub(withdrawAmount).div(1000),
      );
      expect(eventWithdrawal.fundValue).to.be.closeTo(expectedFundValueAfter, expectedFundValueAfter.div(1000));
      expect(eventWithdrawal.totalSupply).to.be.closeTo(
        totalSupply.sub(withdrawAmount),
        totalSupply.sub(withdrawAmount).div(1000),
      );

      const withdrawSUSD = eventWithdrawal.withdrawnAssets[1];
      const withdrawLP = eventWithdrawal.withdrawnAssets[0];
      expect(withdrawSUSD[0]).to.equal(susd);
      expect(withdrawSUSD[2]).to.equal(false);
      expect(withdrawLP[0]).to.equal(sushiLPLinkWeth);
      expect(withdrawLP[2]).to.equal(true);
      expect(eventWithdrawal.withdrawnAssets.length).to.equal(2);
    });

    it("can set Sushi pool ID", async () => {
      expect(sushiLPAssetGuard.setSushiPoolId(ZERO_ADDRESS, "1")).to.be.revertedWith("Invalid lpToken address");

      const contract = "0x1111111111111111111111111111111111111111";
      expect(sushiLPAssetGuard.connect(user1).setSushiPoolId(contract, "1")).to.be.revertedWith(
        "caller is not the owner",
      );

      await sushiLPAssetGuard.setSushiPoolId(contract, "1");
      const poolId = await sushiLPAssetGuard.sushiPoolIds(contract);
      expect(poolId).to.be.equal("1");
    });
  });

  it("should be able to query invested/managed pools", async function () {
    let pools = await poolFactory.getDeployedFunds();

    expect(await poolFactory.getManagedPools(manager.address)).to.be.deep.equal([pools[0]]);
    expect(await poolFactory.getManagedPools(user1.address)).to.be.deep.equal([pools[1]]);

    await poolFactory.createFund(false, manager.address, "Barren Wuffet", "Test Fund", "DHTF", "5000", "200", [
      {
        asset: seth,
        isDeposit: false,
      },
      {
        asset: susd,
        isDeposit: true,
      },
    ]);

    await poolFactory.createFund(false, user1.address, "Barren Wuffet", "Test Fund", "DHTF", "5000", "200", [
      {
        asset: seth,
        isDeposit: false,
      },
      {
        asset: susd,
        isDeposit: true,
      },
    ]);
    pools = await poolFactory.getDeployedFunds();

    expect(await poolFactory.getManagedPools(manager.address)).to.be.deep.equal([pools[0], pools[2]]);
    expect(await poolFactory.getManagedPools(user1.address)).to.be.deep.equal([pools[1], pools[3]]);
    expect(await poolFactory.getManagedPools(logicOwner.address)).to.be.deep.equal([]);

    await assetHandler.setChainlinkTimeout(9000000);

    expect(await poolFactory.getInvestedPools(investor.address)).to.be.deep.equal([pools[0]]);
    expect(await poolFactory.getInvestedPools(logicOwner.address)).to.be.deep.equal([pools[0], pools[1]]);

    const newPoolLogic = await PoolLogic__factory.connect(pools[3], logicOwner);
    const transferFromABI = iERC20.encodeFunctionData("transferFrom", [
      investor.address,
      newPoolLogic.address,
      (100e18).toString(),
    ]);
    await susdProxy.givenCalldataReturnBool(transferFromABI, true);
    await newPoolLogic.connect(investor).deposit(susd, (100e18).toString());

    expect(await poolFactory.getInvestedPools(investor.address)).to.be.deep.equal([pools[0], pools[3]]);
    expect(await poolFactory.getInvestedPools(user2.address)).to.be.deep.equal([]);

    await assetHandler.setChainlinkTimeout(90000);
  });

  it("should be able to upgrade/set implementation logic", async function () {
    await expect(poolFactory.connect(manager).setLogic(TESTNET_DAO, TESTNET_DAO)).to.be.revertedWith(
      "caller is not the owner",
    );
    await poolFactory.setLogic(TESTNET_DAO, TESTNET_DAO);

    const poolManagerLogicAddress = await poolFactory.getLogic(1);
    expect(poolManagerLogicAddress).to.equal(TESTNET_DAO);

    const poolLogicAddress = await poolFactory.getLogic(2);
    expect(poolLogicAddress).to.equal(TESTNET_DAO);

    await poolFactory.setLogic(poolLogic.address, poolManagerLogic.address);
  });

  it("should check dhedge pool restriction", async () => {
    await poolFactory.createFund(false, user1.address, "Barren Wuffet", "Test Fund", "DHTF", "5000", "200", [
      {
        asset: seth,
        isDeposit: false,
      },
      {
        asset: susd,
        isDeposit: true,
      },
    ]);
    let pools = await poolFactory.getDeployedFunds();
    const pool1 = pools[pools.length - 1];

    await poolFactory.createFund(false, user1.address, "Barren Wuffet", "Test Fund", "DHTF", "5000", "200", [
      {
        asset: seth,
        isDeposit: false,
      },
      {
        asset: susd,
        isDeposit: true,
      },
    ]);
    pools = await poolFactory.getDeployedFunds();
    const pool2 = pools[pools.length - 1];

    await poolFactory.createFund(false, user1.address, "Barren Wuffet", "Test Fund", "DHTF", "5000", "200", [
      {
        asset: seth,
        isDeposit: false,
      },
      {
        asset: susd,
        isDeposit: true,
      },
    ]);
    pools = await poolFactory.getDeployedFunds();
    const pool3 = pools[pools.length - 1];

    await assetHandler.addAssets([
      {
        asset: pool1,
        aggregator: usd_price_feed.address,
        assetType: 2,
      },
      {
        asset: pool2,
        aggregator: usd_price_feed.address,
        assetType: 2,
      },
    ]);

    const pool1Logic = await PoolLogic__factory.connect(pool1, logicOwner);
    const pool1ManagerLogic = await PoolManagerLogic__factory.connect(await pool1Logic.poolManagerLogic(), logicOwner);

    await expect(
      pool1ManagerLogic.connect(user1).changeAssets(
        [
          {
            asset: pool2,
            isDeposit: false,
          },
        ],
        [],
      ),
    ).to.revertedWith("cannot add pool asset");

    const pool3Logic = await PoolLogic__factory.connect(pool3, logicOwner);
    const pool3ManagerLogic = await PoolManagerLogic__factory.connect(await pool3Logic.poolManagerLogic(), logicOwner);
    await pool3ManagerLogic.connect(user1).changeAssets(
      [
        {
          asset: pool2,
          isDeposit: false,
        },
      ],
      [],
    );
  });

  it("should be able to add/remove custom cooldown whitelist", async function () {
    await expect(poolFactory.connect(manager).addCustomCooldownWhitelist(user2.address)).to.be.revertedWith(
      "caller is not the owner",
    );
    await expect(poolFactory.connect(manager).removeCustomCooldownWhitelist(user2.address)).to.be.revertedWith(
      "caller is not the owner",
    );
    await poolFactory.addCustomCooldownWhitelist(user2.address);
    await poolFactory.removeCustomCooldownWhitelist(user2.address);
  });

  it("should check the minimum deposit amount", async function () {
    const minDeposit = units(100);
    await expect(poolManagerLogicProxy.setMinDepositUSD(minDeposit)).to.revertedWith("only manager");
    await poolManagerLogicProxy.connect(manager).setMinDepositUSD(minDeposit);

    const transferFromABI = iERC20.encodeFunctionData("transferFrom", [
      user3.address,
      poolLogicProxy.address,
      minDeposit.sub(1),
    ]);
    await susdProxy.givenCalldataReturnBool(transferFromABI, true);

    await expect(poolLogicProxy.connect(user3).deposit(susd, minDeposit.sub(1))).to.revertedWith(
      "must meet minimum deposit",
    );
  });
});
