import { artifacts, ethers, upgrades } from "hardhat";
import { expect } from "chai";
import { Contract } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { Artifact } from "hardhat/types";

import { updateChainlinkAggregators } from "../TestHelpers";
import { MockContract, PoolLogic__factory } from "../../types";
import { Interface } from "@ethersproject/abi";

const { BigNumber, utils } = ethers;

import { units, currentBlockTimestamp } from "../TestHelpers";

const _SYNTHETIX_KEY = "0x53796e7468657469780000000000000000000000000000000000000000000000"; // Synthetix

const susdKey = "0x7355534400000000000000000000000000000000000000000000000000000000";
const sethKey = "0x7345544800000000000000000000000000000000000000000000000000000000";

describe("PoolPerformance", function () {
  let logicOwner: SignerWithAddress, manager: SignerWithAddress, dao: SignerWithAddress, investor: SignerWithAddress;
  let PoolLogic: PoolLogic__factory, poolFactory: Contract, poolLogicProxy: Contract, poolPerformance: Contract;

  let IERC20: Artifact, iERC20: Interface;
  let synthetixGuard; // contract guards
  let erc20Guard; // asset guards
  let addressResolver, synthetix; // integrating contracts
  let susd: string, seth: string;
  let susdAsset: MockContract, susdProxy: MockContract, sethAsset: MockContract, sethProxy: MockContract;
  let usd_price_feed: MockContract, eth_price_feed: MockContract, link_price_feed: MockContract; // integrating aggregators
  beforeEach(async function () {
    [logicOwner, manager, dao, investor] = await ethers.getSigners();

    const MockContract = await ethers.getContractFactory("MockContract");
    addressResolver = await MockContract.deploy();
    synthetix = await MockContract.deploy();
    susdAsset = await MockContract.deploy();
    susdProxy = await MockContract.deploy();
    sethAsset = await MockContract.deploy();
    sethProxy = await MockContract.deploy();
    usd_price_feed = await MockContract.deploy();
    eth_price_feed = await MockContract.deploy();
    link_price_feed = await MockContract.deploy();
    susd = susdProxy.address;
    seth = sethProxy.address;

    // mock IAddressResolver
    const IAddressResolver = await artifacts.readArtifact(
      "contracts/interfaces/synthetix/IAddressResolver.sol:IAddressResolver",
    );
    const iAddressResolver = new ethers.utils.Interface(IAddressResolver.abi);
    const getAddressABI = iAddressResolver.encodeFunctionData("getAddress", [_SYNTHETIX_KEY]);
    await addressResolver.givenCalldataReturnAddress(getAddressABI, synthetix.address);

    // mock ISynthetix
    const ISynthetix = await artifacts.readArtifact("contracts/interfaces/synthetix/ISynthetix.sol:ISynthetix");
    const iSynthetix = new utils.Interface(ISynthetix.abi);
    let synthsABI = iSynthetix.encodeFunctionData("synths", [susdKey]);
    await synthetix.givenCalldataReturnAddress(synthsABI, susdAsset.address);
    synthsABI = iSynthetix.encodeFunctionData("synths", [sethKey]);
    await synthetix.givenCalldataReturnAddress(synthsABI, sethAsset.address);

    let synthsByAddressABI = iSynthetix.encodeFunctionData("synthsByAddress", [susdAsset.address]);
    await synthetix.givenCalldataReturn(synthsByAddressABI, susdKey);
    synthsByAddressABI = iSynthetix.encodeFunctionData("synthsByAddress", [sethAsset.address]);
    await synthetix.givenCalldataReturn(synthsByAddressABI, sethKey);

    // mock ISynth
    const ISynth = await artifacts.readArtifact("contracts/interfaces/synthetix/ISynth.sol:ISynth");
    const iSynth = new utils.Interface(ISynth.abi);
    const proxyABI = iSynth.encodeFunctionData("proxy", []);
    await susdAsset.givenCalldataReturnAddress(proxyABI, susdProxy.address);
    await sethAsset.givenCalldataReturnAddress(proxyABI, sethProxy.address);

    // mock ISynthAddressProxy
    const ISynthAddressProxy = await artifacts.readArtifact(
      "contracts/interfaces/synthetix/ISynthAddressProxy.sol:ISynthAddressProxy",
    );
    const iSynthAddressProxy = new utils.Interface(ISynthAddressProxy.abi);
    const targetABI = iSynthAddressProxy.encodeFunctionData("target", []);
    await susdProxy.givenCalldataReturnAddress(targetABI, susdAsset.address);
    await sethProxy.givenCalldataReturnAddress(targetABI, sethAsset.address);

    IERC20 = await artifacts.readArtifact("ERC20Upgradeable");
    iERC20 = new ethers.utils.Interface(IERC20.abi);
    const decimalsABI = iERC20.encodeFunctionData("decimals", []);
    await susdProxy.givenCalldataReturnUint(decimalsABI, "18");
    await sethProxy.givenCalldataReturnUint(decimalsABI, "18");

    const Governance = await ethers.getContractFactory("Governance");
    const governance = await Governance.deploy();

    const mockAaveProtocolDataProvider = await MockContract.deploy();
    const mockAaveLendingPool = await MockContract.deploy();

    const IAaveProtocolDataProvider = await artifacts.readArtifact(
      "contracts/interfaces/aave/IAaveProtocolDataProvider.sol:IAaveProtocolDataProvider",
    );
    const iAaveProtocolDataProvider = new utils.Interface(IAaveProtocolDataProvider.abi);
    const addressProviderABI = iAaveProtocolDataProvider.encodeFunctionData("ADDRESSES_PROVIDER", []);
    await mockAaveProtocolDataProvider.givenCalldataReturnAddress(addressProviderABI, mockAaveLendingPool.address);

    const PoolPerformance = await ethers.getContractFactory("PoolPerformance");
    poolPerformance = await upgrades.deployProxy(PoolPerformance);
    await poolPerformance.deployed();
    await poolPerformance.enable();

    PoolLogic = await ethers.getContractFactory("PoolLogic");
    const poolLogic = await PoolLogic.deploy();

    const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
    const poolManagerLogic = await PoolManagerLogic.deploy();

    // Initialize Asset Price Consumer
    const assetSusd = { asset: susd, assetType: 0, aggregator: usd_price_feed.address };
    const assetSeth = { asset: seth, assetType: 0, aggregator: eth_price_feed.address };
    const assetHandlerInitAssets = [assetSusd, assetSeth];

    const AssetHandlerLogic = await ethers.getContractFactory(
      "contracts/priceAggregators/AssetHandler.sol:AssetHandler",
    );
    const assetHandler = await upgrades.deployProxy(AssetHandlerLogic, [assetHandlerInitAssets]);
    await assetHandler.deployed();

    const PoolFactoryLogic = await ethers.getContractFactory("PoolFactory");
    poolFactory = await upgrades.deployProxy(PoolFactoryLogic, [
      poolLogic.address,
      poolManagerLogic.address,
      assetHandler.address,
      dao.address,
      governance.address,
    ]);

    await poolFactory.setPoolPerformanceAddress(poolPerformance.address);

    // Deploy contract guards
    const SynthetixGuard = await ethers.getContractFactory(
      "contracts/guards/contractGuards/SynthetixGuard.sol:SynthetixGuard",
    );
    synthetixGuard = await SynthetixGuard.deploy(addressResolver.address);
    synthetixGuard.deployed();

    // Deploy asset guards
    const ERC20Guard = await ethers.getContractFactory("contracts/guards/assetGuards/ERC20Guard.sol:ERC20Guard");
    erc20Guard = await ERC20Guard.deploy();
    erc20Guard.deployed();

    await governance.setAssetGuard(0, erc20Guard.address);
    await governance.setContractGuard(synthetix.address, synthetixGuard.address);

    await updateChainlinkAggregators(usd_price_feed, eth_price_feed, link_price_feed);
  });

  // manager starts pool with $1
  // then direct deposits $1
  // directDepositFactor = $1
  // from here,
  // scenario 1:
  // pool goes down 50% in value (performance drop)
  // Token price returns $1 and tokenPriceAdjustedForPerformance returns $0.5
  it("Scenario 1 - direct deposit equal to aum, 50% drop in asset value", async function () {
    await poolFactory.createFund(
      false,
      manager.address,
      "Barren Wuffet",
      "Test Fund",
      "DHTF",
      BigNumber.from("5000"),
      BigNumber.from("0"), // 0% streaming fee
      [
        [seth, false],
        [susd, true],
      ],
    );
    const funds = await poolFactory.getDeployedFunds();
    expect(funds[0]).not.to.be.undefined;
    poolLogicProxy = await PoolLogic.attach(funds[0]);
    const transferFromABI = iERC20.encodeFunctionData("transferFrom", [
      investor.address,
      poolLogicProxy.address,
      (100e18).toString(),
    ]);
    await susdProxy.givenMethodReturnBool(transferFromABI, true);

    await poolLogicProxy.deposit(susd, (100e18).toString());

    const oneDollar = 1e18;
    const balanceOfABI = iERC20.encodeFunctionData("balanceOf", [poolLogicProxy.address]);
    await susdProxy.givenCalldataReturnUint(balanceOfABI, (100e18).toString());

    expect((await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address)).toString()).to.equal(
      oneDollar.toString(),
    );
    expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
      oneDollar.toString(),
    );

    expect((await poolPerformance.tokenPrice(poolLogicProxy.address)).toString()).to.equal(oneDollar.toString());
    expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
      oneDollar.toString(),
    );

    const twoDollar = 2e18;
    await susdProxy.givenCalldataReturnUint(balanceOfABI, (200e18).toString());

    expect((await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address)).toString()).to.equal(
      twoDollar.toString(),
    );

    const oneDollarSixty = 16e17;
    expect((await poolPerformance.tokenPrice(poolLogicProxy.address)).toString()).to.equal(oneDollarSixty.toString());
    expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
      (oneDollarSixty / 2).toString(),
    );

    const current = await currentBlockTimestamp();
    const AggregatorV3 = await artifacts.readArtifact("AggregatorV3Interface");
    const iAggregatorV3 = new utils.Interface(AggregatorV3.abi);
    const latestRoundDataABI = iAggregatorV3.encodeFunctionData("latestRoundData", []);

    // Halve the usd price
    await usd_price_feed.givenCalldataReturn(
      latestRoundDataABI,
      ethers.utils.solidityPack(["uint256", "int256", "uint256", "uint256", "uint256"], [0, 50000000, 0, current, 0]),
    ); // $.5

    expect((await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address)).toString()).to.equal(
      oneDollar.toString(),
    );
    expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
      (oneDollar / 2).toString(),
    );
    // There is no manager fee because there is no performance because usdc price fell to $.50
    expect((await poolPerformance.tokenPrice(poolLogicProxy.address)).toString()).to.equal(
      await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address),
    );
    expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
      await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address),
    );
  });

  // manager starts pool with $1
  // then direct deposits $1
  // directDepositFactor = 0.5
  // from here,
  // scenario 2:
  // pool goes up 100% in value (performance gain)
  // now token price returns 3? (ie 200% gain)
  // No token price returns $4 (double the underlying value) and tokenPriceAdjustedForPerformance returns $2 (double the deposited value)
  it("Scenario 2 - direct deposit equal to aum, 100% increase in asset value", async function () {
    await poolFactory.createFund(
      false,
      manager.address,
      "Barren Wuffet",
      "Test Fund",
      "DHTF",
      BigNumber.from("5000"),
      BigNumber.from("0"), // 0%
      [
        [seth, false],
        [susd, true],
      ],
    );
    const funds = await poolFactory.getDeployedFunds();
    expect(funds[0]).not.to.be.undefined;
    poolLogicProxy = await PoolLogic.attach(funds[0]);
    const transferFromABI = iERC20.encodeFunctionData("transferFrom", [
      investor.address,
      poolLogicProxy.address,
      (100e18).toString(),
    ]);
    await susdProxy.givenMethodReturnBool(transferFromABI, true);

    await poolLogicProxy.deposit(susd, (100e18).toString());

    const oneDollar = 1e18;
    const balanceOfABI = iERC20.encodeFunctionData("balanceOf", [poolLogicProxy.address]);
    await susdProxy.givenCalldataReturnUint(balanceOfABI, (100e18).toString());

    expect((await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address)).toString()).to.equal(
      oneDollar.toString(),
    );
    expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
      oneDollar.toString(),
    );

    expect((await poolPerformance.tokenPrice(poolLogicProxy.address)).toString()).to.equal(oneDollar.toString());
    expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
      oneDollar.toString(),
    );

    const twoDollar = 2e18;
    await susdProxy.givenCalldataReturnUint(balanceOfABI, (200e18).toString());

    expect((await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address)).toString()).to.equal(
      twoDollar.toString(),
    );

    const oneDollarSixty = 16e17;
    expect((await poolPerformance.tokenPrice(poolLogicProxy.address)).toString()).to.equal(oneDollarSixty.toString());
    expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
      (oneDollarSixty / 2).toString(),
    );

    const current = await currentBlockTimestamp();
    const AggregatorV3 = await artifacts.readArtifact("AggregatorV3Interface");
    const iAggregatorV3 = new utils.Interface(AggregatorV3.abi);
    const latestRoundDataABI = iAggregatorV3.encodeFunctionData("latestRoundData", []);

    // Double the usd price
    await usd_price_feed.givenCalldataReturn(
      latestRoundDataABI,
      ethers.utils.solidityPack(["uint256", "int256", "uint256", "uint256", "uint256"], [0, 200000000, 0, current, 0]),
    ); // $2

    const fourDollar = 4e18;
    // Token price is now $4
    expect((await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address)).toString()).to.equal(
      fourDollar.toString(),
    );

    // The token price is now $4 and $3 of that is profit in the eyes of the contract, the manager is owed .375 tokens roughly $1.5 (50% of profit) at the current token price
    // This means after minting manager fee there would be 1.375 tokens owning $4
    // $4 / 1.375 = $2.919708029 (1 token value)
    const twoDollarNinety = BigNumber.from(BigInt((fourDollar / 1.375) * 1));
    expect((await poolPerformance.tokenPrice(poolLogicProxy.address)).toString()).to.be.closeTo(twoDollarNinety, 100);

    // $2.90 / 2
    expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.be.closeTo(
      twoDollarNinety.div(2),
      100,
    );
  });

  // manager starts pool with $1
  // then direct deposits $10
  // externalValueFactor = 1/10 === 0.1
  // from here,
  // scenario 2:
  // pool goes up 100% in value (performance gain)
  // now token price returns 3? (ie 200% gain)
  // No token price returns $4 (double the underlying value) and tokenPriceAdjustedForPerformance returns $2 (double the deposited value)
  it("Scenario 3 - small aum, large deposit, 100% increase in asset value", async function () {
    await poolFactory.createFund(
      false,
      manager.address,
      "Barren Wuffet",
      "Test Fund",
      "DHTF",
      BigNumber.from("5000"),
      BigNumber.from("0"), // 0%
      [
        [seth, false],
        [susd, true],
      ],
    );
    const funds = await poolFactory.getDeployedFunds();
    expect(funds[0]).not.to.be.undefined;
    poolLogicProxy = await PoolLogic.attach(funds[0]);
    const transferFromABI = iERC20.encodeFunctionData("transferFrom", [
      investor.address,
      poolLogicProxy.address,
      (100e18).toString(),
    ]);
    await susdProxy.givenMethodReturnBool(transferFromABI, true);

    await poolLogicProxy.deposit(susd, (100e18).toString());

    const oneDollar = 1e18;

    const balanceOfABI = iERC20.encodeFunctionData("balanceOf", [poolLogicProxy.address]);
    await susdProxy.givenCalldataReturnUint(balanceOfABI, (100e18).toString());

    expect((await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address)).toString()).to.equal(
      oneDollar.toString(),
    );
    expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
      oneDollar.toString(),
    );

    expect((await poolPerformance.tokenPrice(poolLogicProxy.address)).toString()).to.equal(oneDollar.toString());
    expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
      oneDollar.toString(),
    );

    const tenDollars = 10e18;
    await susdProxy.givenCalldataReturnUint(balanceOfABI, BigNumber.from(BigInt(100e18)).mul(10));

    expect((await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address)).toString()).to.equal(
      tenDollars.toString(),
    );

    const current = await currentBlockTimestamp();
    const AggregatorV3 = await artifacts.readArtifact("AggregatorV3Interface");
    const iAggregatorV3 = new utils.Interface(AggregatorV3.abi);
    const latestRoundDataABI = iAggregatorV3.encodeFunctionData("latestRoundData", []);

    // Double the usd price
    await usd_price_feed.givenCalldataReturn(
      latestRoundDataABI,
      ethers.utils.solidityPack(["uint256", "int256", "uint256", "uint256", "uint256"], [0, 200000000, 0, current, 0]),
    ); // $2

    const twentyDollars = 20e18;
    // Token price is now $4
    expect((await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address)).toString()).to.equal(
      twentyDollars.toString(),
    );

    // The token price is now $20 and $19 of that is profit in the eyes of the contract, the manager is owed 0.475 tokens roughly $9.50 (50% of profit) at the current token price
    // This means after minting manager fee there would be 1.475 tokens owning $9.50
    // $20 / 1.475 = $13.559322034 (1 token value)
    const thirteenFiftyFive = BigNumber.from(BigInt((twentyDollars / 1.475) * 1));
    expect((await poolPerformance.tokenPrice(poolLogicProxy.address)).toString()).to.be.closeTo(
      thirteenFiftyFive,
      10000,
    );

    // $13.55 - minus the direct deposit value of $18 == error
    const tenth = thirteenFiftyFive.div(10);
    expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.be.closeTo(
      tenth,
      10000,
    );
  });

  it("setInternalValueFactor", async function () {
    await poolFactory.createFund(
      false,
      manager.address,
      "Barren Wuffet",
      "Test Fund",
      "DHTF",
      ethers.BigNumber.from("0"),
      ethers.BigNumber.from("0"), // 0%
      [
        [seth, false],
        [susd, true],
      ],
    );

    const funds = await poolFactory.getDeployedFunds();
    expect(funds[0]).not.to.be.undefined;
    poolLogicProxy = await PoolLogic.attach(funds[0]);
    const transferFromABI = iERC20.encodeFunctionData("transferFrom", [
      investor.address,
      poolLogicProxy.address,
      (100e18).toString(),
    ]);
    await susdProxy.givenMethodReturnBool(transferFromABI, true);

    await poolLogicProxy.deposit(susd, (100e18).toString());

    const oneDollar = 1e18;
    const balanceOfABI = iERC20.encodeFunctionData("balanceOf", [poolLogicProxy.address]);
    await susdProxy.givenCalldataReturnUint(balanceOfABI, (100e18).toString());

    expect((await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address)).toString()).to.equal(
      oneDollar.toString(),
    );
    expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
      oneDollar.toString(),
    );

    const twoDollar = 2e18;
    await susdProxy.givenCalldataReturnUint(balanceOfABI, (200e18).toString());

    expect((await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address)).toString()).to.equal(
      twoDollar.toString(),
    );
    expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
      oneDollar.toString(),
    );

    await poolPerformance.recordExternalValue(poolLogicProxy.address);

    expect((await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address)).toString()).to.equal(
      twoDollar.toString(),
    );
    expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
      oneDollar.toString(),
    );

    await poolPerformance.setInternalValueFactor(poolLogicProxy.address, (1e18).toString());

    expect((await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address)).toString()).to.equal(
      twoDollar.toString(),
    );
    expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
      twoDollar.toString(),
    );
  });

  it("setInternalValueFactor only callable by owner", async function () {
    await poolFactory.createFund(
      false,
      manager.address,
      "Barren Wuffet",
      "Test Fund",
      "DHTF",
      BigNumber.from("5000"),
      BigNumber.from("0"), // 0%
      [
        [seth, false],
        [susd, true],
      ],
    );

    const funds = await poolFactory.getDeployedFunds();
    expect(funds[0]).not.to.be.undefined;
    poolLogicProxy = await PoolLogic.attach(funds[0]);

    await poolPerformance.setInternalValueFactor(poolLogicProxy.address, (1e18).toString());

    await expect(
      poolPerformance.connect(manager).setInternalValueFactor(poolLogicProxy.address, (1e18).toString()),
    ).to.be.revertedWith("Ownable: caller is not the owner");
  });

  it("adjustInternalValueFactor 10 percent small number", async function () {
    expect(await poolPerformance.internalValueFactor(logicOwner.address)).to.equal(units(1));
    await poolPerformance.adjustInternalValueFactor(10, 100); // 10%
    const tenPercent1e18 = units(1).div(10);
    expect(await poolPerformance.internalValueFactor(logicOwner.address)).to.equal(units(1).sub(tenPercent1e18));
  });

  it("adjustInternalValueFactor 5% of massive number", async function () {
    expect(await poolPerformance.internalValueFactor(logicOwner.address)).to.equal(units(1));
    const fivePercent = units(100).div(20);
    await poolPerformance.adjustInternalValueFactor(fivePercent, units(100)); // 5%
    const fivePercent1e18 = units(1).div(20);
    expect(await poolPerformance.internalValueFactor(logicOwner.address)).to.equal(units(1).sub(fivePercent1e18));
  });

  it("adjustInternalValueFactor 0.1% of massive number", async function () {
    expect(await poolPerformance.internalValueFactor(logicOwner.address)).to.equal(units(1));
    const zeroPointOnePercent = units(100).div(1000);
    await poolPerformance.adjustInternalValueFactor(zeroPointOnePercent, BigInt(100e18)); // 0.1%
    const zeroPointOnePercentOf1e18 = units(1).div(1000);
    expect(await poolPerformance.internalValueFactor(logicOwner.address)).to.equal(
      units(1).sub(zeroPointOnePercentOf1e18),
    );
  });

  it("adjustInternalValueFactor 10 percent twice", async function () {
    expect(await poolPerformance.internalValueFactor(logicOwner.address)).to.equal(units(1));
    await poolPerformance.adjustInternalValueFactor(10, 100); // 10%
    const tenPercent1e18 = units(1).div(10);
    expect(await poolPerformance.internalValueFactor(logicOwner.address)).to.equal(units(1).sub(tenPercent1e18));
    await poolPerformance.adjustInternalValueFactor(10, 100); // 10%
    const ninePercent1e18 = units(90).div(1000);
    //1 * 0.9 * 0.9 = 0.81
    expect(await poolPerformance.internalValueFactor(logicOwner.address)).to.equal(
      units(1).sub(tenPercent1e18).sub(ninePercent1e18),
    );
  });
});
