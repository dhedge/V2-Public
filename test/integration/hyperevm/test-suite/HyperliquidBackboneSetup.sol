// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import {TransparentUpgradeableProxy} from "@openzeppelin/v5/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Test} from "forge-std/Test.sol";

import {IPoolFactory} from "contracts/interfaces/IPoolFactory.sol";
import {IPoolLogic} from "contracts/interfaces/IPoolLogic.sol";
import {IERC20Extended} from "contracts/interfaces/IERC20Extended.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {HyperEVMConfig} from "test/integration/utils/foundry/config/HyperEVMConfig.sol";

/// @notice Simplified backbone setup for Hyperliquid integration tests using deployCode
/// @dev This is needed because CoreSimulatorLib uses Solidity ^0.8.0 but the main
///      dHEDGE contracts use 0.7.6. We use deployCode to deploy 0.7.6 contracts.
abstract contract HyperliquidBackboneSetup is Test {
  enum AssetTypeIncomplete {
    CHAINLINK, // 0
    SNX_SYNTH, // 1
    SUSHI_LP, // 2
    AAVE_V2, // 3
    LENDING_ENABLED, // 4
    QUICK_LP, // 5
    BALANCER_LP, // 6
    UNISWAP_V3, // 7
    AAVE_V3, // 8
    ARRAKIS_GAUGE, // 9
    BALANCER_V2_GAUGE, // 10
    NOT_ASSIGNED_0, // 11
    NOT_ASSIGNED_1, // 12
    NOT_ASSIGNED_2, // 13
    SNX_SYNTH_LENDING_ENABLED, // 14
    VELODROME_LP, // 15
    STARGATE_LP, // 16
    MAI_VAULT, // 17
    NOT_ASSIGNED_3, // 18
    NOT_ASSIGNED_4, // 19
    RAMSES_LP, // 20
    FLAT_MONEY_UNIT, // 21
    FLAT_MONEY_COLLATERAL, // 22
    NOT_ASSGIGNED_5, // 23
    NOT_ASSIGNED_6, // 24
    VELODROME_V2_LP, // 25
    VELODROME_CL, // 26
    FLAT_MONEY_LEVERAGE, // 27
    COMPOUND_V3_COMET, // 28
    RAMSES_CL, // 29
    EASYSWAPPER_V2_UNROLLED, // 30
    PANCAKE_CL, // 31
    FLAT_MONEY_OPTIONS_MARKET, // 32
    FLAT_MONEY_COLLATERAL_LENDING_ENABLED, // 33
    FLUID_TOKEN, // 34
    FLAT_MONEY_V2_UNIT, // 35
    FLAT_MONEY_V2_PERP_MARKET, // 36
    PENDLE_PRINCIPAL_TOKEN, // 37
    VIRTUAL_TOKEN, // 38
    HYPERLIQUID_PERPS_ASSET, // 39
    HYPERLIQUID_SPOT // 40
  }

  /* Roles */
  address public owner = makeAddr("owner");
  address public dao = makeAddr("dao");
  address public manager = makeAddr("manager");
  address public investor = makeAddr("investor");

  /* Infrastructure Contracts */
  IGovernanceTest public governance;
  address public proxyAdmin;
  address public poolLogic;
  address public poolManagerLogic;
  address public assetHandler;
  IAssetHandlerTest public assetHandlerProxy;
  address public poolFactory;
  IPoolFactory public poolFactoryProxy;
  address public slippageAccumulator;
  address public usdPriceAggregator;
  address public hyperliquidERC20Guard;
  address public nftTrackerStorage;
  INftTrackerStorageTest public nftTrackerStorageProxy;
  address public withdrawalVault;
  address public easySwapperV2;
  IEasySwapperV2Test public easySwapperV2Proxy;

  function setUp() public virtual {
    vm.startPrank(owner);

    // Deploy implementation contracts using deployCode
    proxyAdmin = deployCode("ProxyAdmin.sol", abi.encode(owner));
    governance = IGovernanceTest(deployCode("Governance.sol"));
    poolLogic = deployCode("PoolLogic.sol");
    poolManagerLogic = deployCode("PoolManagerLogic.sol");
    assetHandler = deployCode("AssetHandler.sol");
    poolFactory = deployCode("PoolFactory.sol");
    usdPriceAggregator = deployCode("USDPriceAggregator.sol");
    hyperliquidERC20Guard = deployCode("HyperliquidERC20Guard.sol");
    nftTrackerStorage = deployCode("DhedgeNftTrackerStorage.sol");
    withdrawalVault = deployCode("WithdrawalVault.sol");

    // Deploy proxies
    assetHandlerProxy = IAssetHandlerTest(address(new TransparentUpgradeableProxy(assetHandler, proxyAdmin, "")));
    poolFactoryProxy = IPoolFactory(address(new TransparentUpgradeableProxy(poolFactory, proxyAdmin, "")));

    // Deploy SlippageAccumulator
    slippageAccumulator = deployCode("SlippageAccumulator.sol", abi.encode(address(poolFactoryProxy), 21600, 5e4)); // 6 hours, 5%

    // Deploy NftTrackerStorage proxy
    nftTrackerStorageProxy = INftTrackerStorageTest(
      address(new TransparentUpgradeableProxy(nftTrackerStorage, proxyAdmin, ""))
    );

    // Deploy EasySwapperV2
    easySwapperV2 = deployCode("EasySwapperV2.sol");
    easySwapperV2Proxy = IEasySwapperV2Test(address(new TransparentUpgradeableProxy(easySwapperV2, proxyAdmin, "")));

    // Initialize contracts
    // Note: We need to encode the initialization calls and execute them

    // Initialize NftTrackerStorage
    nftTrackerStorageProxy.initialize(address(poolFactoryProxy));

    // Initialize AssetHandler with no assets
    IAssetHandlerTest.Asset[] memory assets = new IAssetHandlerTest.Asset[](0);
    assetHandlerProxy.initialize(assets);

    // Initialize PoolFactory
    poolFactoryProxy.initialize(poolLogic, poolManagerLogic, address(assetHandlerProxy), dao, address(governance));

    // Initialize EasySwapperV2
    easySwapperV2Proxy.initialize(
      address(poolFactoryProxy),
      withdrawalVault,
      address(nftTrackerStorageProxy),
      HyperEVMConfig.WHYPE_TOKEN_ADDRESS,
      5 minutes // 5 minutes custom cooldown
    );

    // Set a shorter exit cooldown (5 minutes - minimum allowed) for testing purposes
    // This avoids timestamp overflow issues when using skip()
    (bool success, ) = address(poolFactoryProxy).call(abi.encodeWithSignature("setExitCooldown(uint256)", 5 minutes));
    require(success, "setExitCooldown failed");

    // Set dHedgePoolFactory on EasySwapperV2
    easySwapperV2Proxy.setdHedgePoolFactory(address(poolFactoryProxy));

    // Add custom cooldown whitelist
    poolFactoryProxy.addCustomCooldownWhitelist(address(easySwapperV2Proxy));

    governance.setAssetGuard(uint16(AssetTypeIncomplete.CHAINLINK), hyperliquidERC20Guard);

    vm.stopPrank();
  }

  /// @dev Helper to make deposits (simplified for Hyperliquid tests)
  function _makeDeposit(address _pool, address _asset, uint256 _amount) internal returns (uint256 liquidityMinted) {
    // Approve asset
    IERC20Extended(_asset).approve(_pool, _amount);

    // Deposit
    liquidityMinted = IPoolLogic(_pool).deposit(_asset, _amount);
  }
}

/// @notice Test-only interface for Governance contract
interface IGovernanceTest {
  function setContractGuard(address extContract, address guardAddress) external;

  function setAssetGuard(uint16 assetType, address guardAddress) external;

  function owner() external view returns (address);
}

/// @notice Test-only interface for AssetHandler contract
interface IAssetHandlerTest {
  struct Asset {
    address asset;
    uint16 assetType;
    address aggregator;
  }

  function initialize(Asset[] memory assets) external;

  function addAsset(address asset, uint16 assetType, address aggregator) external;
}

/// @notice Test-only interface for DhedgeNftTrackerStorage contract
interface INftTrackerStorageTest {
  function initialize(address _poolFactory) external;
}

/// @notice Test-only interface for EasySwapperV2 contract
interface IEasySwapperV2Test {
  function initialize(
    address _poolFactory,
    address _withdrawalVault,
    address _nftTrackerStorage,
    address _feeSink,
    uint256 _customCooldown
  ) external;

  function setdHedgePoolFactory(address _poolFactory) external;
}

interface IChangeAssets {
  function changeAssets(IHasSupportedAsset.Asset[] calldata assetsToAdd, address[] calldata assetsToRemove) external;
}
