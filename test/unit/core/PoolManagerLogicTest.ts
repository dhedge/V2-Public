import { ethers, artifacts, upgrades } from "hardhat";
import { expect } from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { Contract, ContractFactory } from "ethers";

import { toBytes32 } from "../../testHelpers";
const { BigNumber } = ethers;

const externalValidToken = "0xb79fad4ca981472442f53d16365fdf0305ffd8e9"; //random address
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

describe("RemoveAssets", function () {
  let poolFactory: Contract,
    PoolLogic: ContractFactory,
    PoolManagerLogic: ContractFactory,
    aaveProtocolDataProvider: Contract;

  let manager: SignerWithAddress, dao: SignerWithAddress;
  let dai: Contract, aDai: Contract, aDaiVariableDebt: Contract, aDaiStableDebt: Contract, usdc: Contract;

  before(async function () {
    [, manager, dao] = await ethers.getSigners();

    const MockContract = await ethers.getContractFactory("MockContract");

    const usd_price_feed = await MockContract.deploy();
    const aaveLendingPool = await MockContract.deploy();
    dai = await MockContract.deploy();
    aDai = await MockContract.deploy();
    aDaiVariableDebt = await MockContract.deploy();
    aDaiStableDebt = await MockContract.deploy();
    usdc = await MockContract.deploy();
    aaveProtocolDataProvider = await MockContract.deploy();

    const aaveLendingPoolAssetGuard = await MockContract.deploy();

    // mock IAaveProtocolDataProvider
    const IAaveProtocolDataProvider = await artifacts.readArtifact("IAaveProtocolDataProvider");
    const iAaveProtocolDataProvider = new ethers.utils.Interface(IAaveProtocolDataProvider.abi);

    const IERC20 = await artifacts.readArtifact("ERC20Upgradeable");
    const iERC20 = new ethers.utils.Interface(IERC20.abi);
    const decimalsABI = iERC20.encodeFunctionData("decimals", []);
    await aaveLendingPool.givenCalldataReturnUint(decimalsABI, "18");
    await dai.givenCalldataReturnUint(decimalsABI, "18");
    await usdc.givenCalldataReturnUint(decimalsABI, "18");
    await aaveLendingPoolAssetGuard.givenCalldataReturnUint(decimalsABI, "18");

    const Governance = await ethers.getContractFactory("Governance");
    const governance = await Governance.deploy();
    console.log("governance deployed to:", governance.address);

    PoolLogic = await ethers.getContractFactory("PoolLogic");
    const poolLogic = await PoolLogic.deploy();

    PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
    const poolManagerLogic = await PoolManagerLogic.deploy();

    // Deploy USD Price Aggregator
    const USDPriceAggregator = await ethers.getContractFactory("USDPriceAggregator");
    const usdPriceAggregator = await USDPriceAggregator.deploy();

    const assetLendingPool = { asset: aaveLendingPool.address, assetType: 3, aggregator: usdPriceAggregator.address };
    const assetDai = { asset: dai.address, assetType: 4, aggregator: usd_price_feed.address }; // Lending enabled
    const assetUsdc = { asset: usdc.address, assetType: 4, aggregator: usd_price_feed.address }; // Lending enabled

    await aaveProtocolDataProvider.givenCalldataReturn(
      iAaveProtocolDataProvider.encodeFunctionData("getReserveTokensAddresses", [usdc.address]),
      ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "address"],
        [ZERO_ADDRESS, ZERO_ADDRESS, ZERO_ADDRESS],
      ),
    );

    await aaveProtocolDataProvider.givenCalldataReturn(
      iAaveProtocolDataProvider.encodeFunctionData("getReserveTokensAddresses", [dai.address]),
      ethers.utils.defaultAbiCoder.encode(
        ["address", "address", "address"],
        [aDai.address, aDaiVariableDebt.address, aDaiStableDebt.address],
      ),
    );

    const assetHandlerInitAssets = [assetLendingPool, assetDai, assetUsdc];

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

    // Deploy asset guards
    const ERC20Guard = await ethers.getContractFactory("contracts/guards/assetGuards/ERC20Guard.sol:ERC20Guard");
    const erc20Guard = await ERC20Guard.deploy();
    erc20Guard.deployed();

    const LendingEnabledAssetGuard = await ethers.getContractFactory("LendingEnabledAssetGuard");
    const lendingEnabledAssetGuard = await LendingEnabledAssetGuard.deploy();
    await lendingEnabledAssetGuard.deployed();

    const OpenAssetGuard = await ethers.getContractFactory(
      "contracts/guards/assetGuards/OpenAssetGuard.sol:OpenAssetGuard",
    );
    const openAssetGuard = await OpenAssetGuard.deploy([externalValidToken]); // initialise with random external token
    openAssetGuard.deployed();

    await governance.setAssetGuard(0, erc20Guard.address);
    await governance.setAssetGuard(1, erc20Guard.address);
    1;
    await governance.setAssetGuard(3, aaveLendingPoolAssetGuard.address);
    await governance.setAssetGuard(4, lendingEnabledAssetGuard.address);
    await governance.setAddresses([{ name: toBytes32("openAssetGuard"), destination: openAssetGuard.address }]);
    await governance.setAddresses([
      { name: toBytes32("aaveProtocolDataProviderV2"), destination: aaveProtocolDataProvider.address },
    ]);
  });

  it("should not be able to remove asset with open aave atoken position", async function () {
    await poolFactory.createFund(
      false,
      manager.address,
      "Barren Wuffet",
      "Test Fund",
      "DHTF",
      BigNumber.from("5000"),
      BigNumber.from("0"),
      [
        [usdc.address, true],
        [dai.address, true],
      ],
    );
    const funds = await poolFactory.getDeployedFunds();
    expect(funds[0]).not.to.be.undefined;
    const poolLogicProxy = await PoolLogic.attach(funds[0]);

    const poolManagerLogicProxyAddress = await poolLogicProxy.poolManagerLogic();
    const poolManagerLogicProxy = await PoolManagerLogic.attach(poolManagerLogicProxyAddress);

    const poolManagerLogicManagerProxy = poolManagerLogicProxy.connect(manager);

    expect((await poolManagerLogicManagerProxy.getSupportedAssets()).length).to.eq(2);

    // Can remove asset
    await poolManagerLogicManagerProxy.changeAssets([], [dai.address]);

    expect((await poolManagerLogicManagerProxy.getSupportedAssets()).length).to.eq(1);

    // Add it back
    await poolManagerLogicManagerProxy.changeAssets([[dai.address, true]], []);

    const IERC20 = await artifacts.readArtifact("ERC20Upgradeable");
    const iERC20 = new ethers.utils.Interface(IERC20.abi);
    const balanceOfABI = iERC20.encodeFunctionData("balanceOf", [poolLogicProxy.address]);
    await aDai.givenCalldataReturnUint(balanceOfABI, 1);

    await expect(poolManagerLogicManagerProxy.changeAssets([], [dai.address])).to.be.revertedWith(
      "withdraw Aave collateral first",
    );
  });

  it("should not be able to remove asset with open aave stable debt position", async function () {
    await poolFactory.createFund(
      false,
      manager.address,
      "Barren Wuffet",
      "Test Fund",
      "DHTF",
      BigNumber.from("5000"),
      BigNumber.from("0"),
      [
        [usdc.address, true],
        [dai.address, true],
      ],
    );
    const funds = await poolFactory.getDeployedFunds();
    expect(funds[0]).not.to.be.undefined;
    const poolLogicProxy = await PoolLogic.attach(funds[0]);

    const poolManagerLogicProxy = await PoolManagerLogic.attach(await poolLogicProxy.poolManagerLogic());

    const poolManagerLogicManagerProxy = poolManagerLogicProxy.connect(manager);

    const IERC20 = await artifacts.readArtifact("ERC20Upgradeable");
    const iERC20 = new ethers.utils.Interface(IERC20.abi);
    const balanceOfABI = iERC20.encodeFunctionData("balanceOf", [poolLogicProxy.address]);
    await aDaiStableDebt.givenCalldataReturnUint(balanceOfABI, 1);

    await expect(poolManagerLogicManagerProxy.changeAssets([], [dai.address])).to.be.revertedWith(
      "repay Aave debt first",
    );
  });

  it("should not be able to remove asset with open aave variable debt position", async function () {
    await poolFactory.createFund(
      false,
      manager.address,
      "Barren Wuffet",
      "Test Fund",
      "DHTF",
      BigNumber.from("5000"),
      BigNumber.from("0"),
      [
        [usdc.address, true],
        [dai.address, true],
      ],
    );
    const funds = await poolFactory.getDeployedFunds();
    expect(funds[0]).not.to.be.undefined;
    const poolLogicProxy = await PoolLogic.attach(funds[0]);

    const poolManagerLogicProxy = await PoolManagerLogic.attach(await poolLogicProxy.poolManagerLogic());

    const poolManagerLogicManagerProxy = poolManagerLogicProxy.connect(manager);

    const IERC20 = await artifacts.readArtifact("ERC20Upgradeable");
    const iERC20 = new ethers.utils.Interface(IERC20.abi);
    const balanceOfABI = iERC20.encodeFunctionData("balanceOf", [poolLogicProxy.address]);
    await aDaiVariableDebt.givenCalldataReturnUint(balanceOfABI, 1);

    await expect(poolManagerLogicManagerProxy.changeAssets([], [dai.address])).to.be.revertedWith(
      "repay Aave debt first",
    );
  });
});
