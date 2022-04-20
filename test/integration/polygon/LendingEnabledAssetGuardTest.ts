import { ethers, artifacts, upgrades } from "hardhat";
import { use, expect } from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { Contract, ContractFactory } from "ethers";
import { solidity } from "ethereum-waffle";

const { BigNumber } = ethers;
use(solidity);

import { toBytes32, units } from "../../TestHelpers";
import { sushi, aaveV2, assets, price_feeds } from "../../../config/chainData/polygon-data";

describe("LendingEnabledAssetGuard", function () {
  let USDC: Contract, WMatic: Contract;
  let logicOwner: SignerWithAddress, manager: SignerWithAddress, dao: SignerWithAddress;
  let PoolLogic: ContractFactory, PoolManagerLogic: ContractFactory;
  let poolFactory: Contract, poolLogicProxy: Contract;

  beforeEach(async function () {
    [logicOwner, manager, dao] = await ethers.getSigners();

    const AssetHandlerLogic = await ethers.getContractFactory("AssetHandler");

    const Governance = await ethers.getContractFactory("Governance");
    const governance = await Governance.deploy();

    const PoolPerformance = await ethers.getContractFactory("PoolPerformance");
    const poolPerformance = await upgrades.deployProxy(PoolPerformance);
    await poolPerformance.deployed();

    PoolLogic = await ethers.getContractFactory("PoolLogic");
    const poolLogic = await PoolLogic.deploy();

    PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
    const poolManagerLogic = await PoolManagerLogic.deploy();

    // Initialize Asset Price Consumer
    const assetWmatic = { asset: assets.wmatic, assetType: 0, aggregator: price_feeds.matic };
    // IMPORTANT: below must be assetType: 4 -> LendingEnabledAssetGuard
    const assetUsdc = { asset: assets.usdc, assetType: 4, aggregator: price_feeds.usdc };
    const assetHandlerInitAssets = [assetWmatic, assetUsdc];

    const assetHandler = await upgrades.deployProxy(AssetHandlerLogic, [assetHandlerInitAssets]);
    await assetHandler.deployed();
    await assetHandler.setChainlinkTimeout((3600 * 24 * 365).toString()); // 1 year expiry

    const PoolFactory = await ethers.getContractFactory("PoolFactory");
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
    const erc20Guard = await ERC20Guard.deploy();
    erc20Guard.deployed();

    await governance.setAssetGuard(0, erc20Guard.address);

    const USDPriceAggregator = await ethers.getContractFactory("USDPriceAggregator");
    const usdPriceAggregator = await USDPriceAggregator.deploy();
    const assetLendingPool = { asset: aaveV2.lendingPool, assetType: 3, aggregator: usdPriceAggregator.address };

    const AaveLendingPoolAssetGuard = await ethers.getContractFactory("AaveLendingPoolAssetGuard");
    const aaveLendingPoolAssetGuard = await AaveLendingPoolAssetGuard.deploy(
      aaveV2.protocolDataProvider,
      aaveV2.lendingPool,
    );
    aaveLendingPoolAssetGuard.deployed();

    const AaveLendingPoolGuard = await ethers.getContractFactory("AaveLendingPoolGuardV2");
    const aaveLendingPoolGuard = await AaveLendingPoolGuard.deploy();
    aaveLendingPoolGuard.deployed();

    const LendingEnabledAssetGuard = await ethers.getContractFactory("LendingEnabledAssetGuard");
    const lendingEnabledAssetGuard = await LendingEnabledAssetGuard.deploy();
    lendingEnabledAssetGuard.deployed();

    const AaveIncentivesControllerGuard = await ethers.getContractFactory("AaveIncentivesControllerGuard");
    const aaveIncentivesControllerGuard = await AaveIncentivesControllerGuard.deploy(assets.wmatic);
    aaveIncentivesControllerGuard.deployed();

    await governance.setAssetGuard(3, aaveLendingPoolAssetGuard.address);
    await governance.setAssetGuard(4, lendingEnabledAssetGuard.address);
    await governance.setContractGuard(aaveV2.lendingPool, aaveLendingPoolGuard.address);
    await governance.setContractGuard(aaveV2.incentivesController, aaveIncentivesControllerGuard.address);

    const OpenAssetGuard = await ethers.getContractFactory("OpenAssetGuard");
    const openAssetGuard = await OpenAssetGuard.deploy([]);
    await openAssetGuard.deployed();

    await governance.setAddresses([
      // [toBytes32("swapRouter"), sushi.router],
      { name: toBytes32("aaveProtocolDataProviderV2"), destination: aaveV2.protocolDataProvider },
      { name: toBytes32("openAssetGuard"), destination: openAssetGuard.address },
    ]);
    await assetHandler.addAssets([assetLendingPool]);

    // Setup LogicOwner with some USDC
    const IWETH = await artifacts.readArtifact("IWETH");
    WMatic = await ethers.getContractAt(IWETH.abi, assets.wmatic);
    const IERC20 = await artifacts.readArtifact("IERC20");

    USDC = await ethers.getContractAt(IERC20.abi, assets.usdc);

    const IUniswapV2Router = await artifacts.readArtifact("IUniswapV2Router");
    const sushiswapRouter = await ethers.getContractAt(IUniswapV2Router.abi, sushi.router);

    await WMatic.deposit({ value: units(500) });

    // Get USDC
    await WMatic.approve(sushi.router, units(1000));
    await sushiswapRouter.swapExactTokensForTokens(
      units(500),
      0,
      [assets.wmatic, assets.usdc],
      logicOwner.address,
      Math.floor(Date.now() / 1000 + 100000000),
    );
  });

  it("cannot remove asset with open aave position", async () => {
    const usdcAmount = (100e6).toString();
    const managerFee = BigNumber.from("0"); // 0%;
    // Create the fund we're going to use for testing
    await poolFactory.createFund(
      false,
      manager.address,
      "Barren Wuffet",
      "Test Fund",
      "DHTF",
      managerFee,
      BigNumber.from("0"),
      [
        [assets.wmatic, true],
        [assets.usdc, true],
        [aaveV2.lendingPool, false],
      ],
    );
    const funds = await poolFactory.getDeployedFunds();
    poolLogicProxy = await PoolLogic.attach(funds[0]);
    // Deposit
    await USDC.approve(poolLogicProxy.address, usdcAmount);
    await poolLogicProxy.deposit(assets.usdc, usdcAmount);

    const IERC20 = await artifacts.readArtifact("IERC20");
    const iERC20 = new ethers.utils.Interface(IERC20.abi);
    // approve usdc
    const approveABI = iERC20.encodeFunctionData("approve", [aaveV2.lendingPool, usdcAmount]);
    await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);

    const ILendingPool = await artifacts.readArtifact("ILendingPool");
    const iLendingPool = new ethers.utils.Interface(ILendingPool.abi);
    // deposit
    const depositABI = iLendingPool.encodeFunctionData("deposit", [assets.usdc, usdcAmount, poolLogicProxy.address, 0]);
    await poolLogicProxy.connect(manager).execTransaction(aaveV2.lendingPool, depositABI);

    const poolManagerLogicProxy = await PoolManagerLogic.attach(await poolLogicProxy.poolManagerLogic());
    const poolManagerLogicManagerProxy = poolManagerLogicProxy.connect(manager);

    expect(await USDC.balanceOf(poolLogicProxy.address)).to.be.equal((0).toString());
    expect(await poolManagerLogicManagerProxy.assetBalance(assets.usdc)).to.be.equal((0).toString());

    await expect(poolManagerLogicManagerProxy.changeAssets([], [assets.usdc])).to.be.revertedWith(
      "withdraw Aave collateral first",
    );
  });
});
