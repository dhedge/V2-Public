// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import {TransparentUpgradeableProxy} from "@openzeppelin/v5/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Test} from "forge-std/Test.sol";

import {IPoolFactory} from "contracts/interfaces/IPoolFactory.sol";
import {IPoolLogic} from "contracts/interfaces/IPoolLogic.sol";
import {IERC20Extended} from "contracts/interfaces/IERC20Extended.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {AssetTypes} from "test/integration/utils/foundry/AssetTypes.sol";

/// @notice Minimal dHEDGE infrastructure setup using deployCode.
/// @dev Uses deployCode() instead of `new` so it can be extended by test contracts that import
///      0.8.x-only libraries (e.g. CoreSimulatorLib which pulls in OZ v5 ERC20).
abstract contract CoreBackboneSetup is Test, AssetTypes {
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

    // Deploy proxies
    assetHandlerProxy = IAssetHandlerTest(address(new TransparentUpgradeableProxy(assetHandler, proxyAdmin, "")));
    poolFactoryProxy = IPoolFactory(address(new TransparentUpgradeableProxy(poolFactory, proxyAdmin, "")));

    // Deploy SlippageAccumulator
    slippageAccumulator = deployCode("SlippageAccumulator.sol", abi.encode(address(poolFactoryProxy), 21600, 5e4)); // 6 hours, 5%

    // Initialize AssetHandler with no assets
    IAssetHandlerTest.Asset[] memory assets = new IAssetHandlerTest.Asset[](0);
    assetHandlerProxy.initialize(assets);

    // Initialize PoolFactory
    poolFactoryProxy.initialize(poolLogic, poolManagerLogic, address(assetHandlerProxy), dao, address(governance));

    // Set a shorter exit cooldown (5 minutes - minimum allowed) for testing purposes
    // This avoids timestamp overflow issues when using skip()
    (bool success, ) = address(poolFactoryProxy).call(abi.encodeWithSignature("setExitCooldown(uint256)", 5 minutes));
    require(success, "setExitCooldown failed");

    vm.stopPrank();
  }

  function _makeDeposit(address _pool, address _asset, uint256 _amount) internal returns (uint256 liquidityMinted) {
    IERC20Extended(_asset).approve(_pool, _amount);
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

interface IChangeAssets {
  function changeAssets(IHasSupportedAsset.Asset[] calldata assetsToAdd, address[] calldata assetsToRemove) external;
}
