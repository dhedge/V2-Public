// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/ProxyAdmin.sol";

import {Governance} from "contracts/Governance.sol";
import {PoolFactory} from "contracts/PoolFactory.sol";
import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {AssetHandler} from "contracts/priceAggregators/AssetHandler.sol";
import {IAssetHandler} from "contracts/interfaces/IAssetHandler.sol";
import {ERC20Guard} from "contracts/guards/assetGuards/ERC20Guard.sol";
import {TestUSDC, TestWETH} from "contracts/test/TestAssets.sol";
import {IAggregatorV3Interface} from "contracts/interfaces/IAggregatorV3Interface.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {PoolTestHelpers} from "test/integration/utils/foundry/PoolTestHelpers.t.sol";

/// @notice A whole dHEDGE core deployed against locally minted tokens and mocked price feeds, with
/// no fork. Suited to core accounting rules that do not depend on any real protocol.
/// @dev Deliberately not built on `BackboneSetup`/`CoreBackboneSetup`: both take real on-chain
/// asset and oracle addresses, which is exactly what these tests need to avoid.
abstract contract PoolUnitTestSetup is PoolTestHelpers {
  uint256 internal constant EXIT_COOLDOWN = 1 days;
  uint256 internal constant USDC_PRICE = 1e8; // $1, Chainlink 8 decimals
  uint256 internal constant WETH_PRICE = 2_000e8; // $2000

  address internal owner = makeAddr("owner");
  address internal dao = makeAddr("dao");
  address internal manager = makeAddr("manager");
  address internal investor = makeAddr("investor");
  address internal otherInvestor = makeAddr("otherInvestor");

  address internal usdcPriceFeed = makeAddr("usdcPriceFeed");
  address internal wethPriceFeed = makeAddr("wethPriceFeed");

  Governance internal governance;
  AssetHandler internal assetHandlerProxy;
  PoolFactory internal poolFactoryProxy;
  TestUSDC internal usdc;
  TestWETH internal weth;

  PoolLogic internal fund;
  PoolManagerLogic internal fundManagerLogic;

  function setUp() public virtual {
    usdc = new TestUSDC(20_000_000);
    weth = new TestWETH(2_000_000);

    _mockPriceFeed(usdcPriceFeed, USDC_PRICE);
    _mockPriceFeed(wethPriceFeed, WETH_PRICE);

    vm.startPrank(owner);

    address proxyAdmin = address(new ProxyAdmin());
    governance = new Governance();
    governance.setAssetGuard({assetType: 0, guardAddress: address(new ERC20Guard())});

    IAssetHandler.Asset[] memory assets = new IAssetHandler.Asset[](2);
    assets[0] = IAssetHandler.Asset({asset: address(usdc), assetType: 0, aggregator: usdcPriceFeed});
    assets[1] = IAssetHandler.Asset({asset: address(weth), assetType: 0, aggregator: wethPriceFeed});

    assetHandlerProxy = AssetHandler(
      address(new TransparentUpgradeableProxy(address(new AssetHandler()), proxyAdmin, ""))
    );
    assetHandlerProxy.initialize(assets);
    // The mocked feeds report a fixed timestamp while these tests move the clock around.
    assetHandlerProxy.setChainlinkTimeout(3650 days);

    poolFactoryProxy = PoolFactory(
      address(new TransparentUpgradeableProxy(address(new PoolFactory()), proxyAdmin, ""))
    );
    poolFactoryProxy.initialize({
      _poolLogic: address(new PoolLogic()),
      _managerLogic: address(new PoolManagerLogic()),
      _assetHandlerAddress: address(assetHandlerProxy),
      _daoAddress: dao,
      _governanceAddress: address(governance)
    });
    poolFactoryProxy.setExitCooldown(EXIT_COOLDOWN);

    vm.stopPrank();

    IHasSupportedAsset.Asset[] memory supportedAssets = new IHasSupportedAsset.Asset[](2);
    supportedAssets[0] = IHasSupportedAsset.Asset({asset: address(usdc), isDeposit: true});
    supportedAssets[1] = IHasSupportedAsset.Asset({asset: address(weth), isDeposit: true});

    vm.prank(manager);
    fund = PoolLogic(
      poolFactoryProxy.createFund({
        _privatePool: false,
        _manager: manager,
        _managerName: "Manager",
        _fundName: "PoolUnitTest",
        _fundSymbol: "PUT",
        _performanceFeeNumerator: 0,
        _managerFeeNumerator: 0,
        _entryFeeNumerator: 0,
        _exitFeeNum: 0,
        _supportedAssets: supportedAssets
      })
    );
    fundManagerLogic = PoolManagerLogic(fund.poolManagerLogic());

    _fund(manager);
    _fund(investor);
    _fund(otherInvestor);
  }

  function _fund(address _account) internal {
    usdc.transfer(_account, 1_000_000e6);
    weth.transfer(_account, 100e18);

    vm.startPrank(_account);
    usdc.approve(address(fund), type(uint256).max);
    weth.approve(address(fund), type(uint256).max);
    vm.stopPrank();
  }

  function _deposit(address _depositor, address _asset, uint256 _amount) internal returns (uint256 liquidityMinted) {
    vm.prank(_depositor);
    liquidityMinted = fund.deposit(_asset, _amount);
  }

  function _withdraw(address _withdrawer, uint256 _shares) internal {
    vm.prank(_withdrawer);
    fund.withdraw(_shares);
  }

  function _mockPriceFeed(address _feed, uint256 _price) internal {
    vm.mockCall(
      _feed,
      abi.encodeWithSelector(IAggregatorV3Interface.latestRoundData.selector),
      abi.encode(uint80(0), int256(_price), uint256(0), block.timestamp, uint80(0))
    );
    vm.mockCall(_feed, abi.encodeWithSelector(IAggregatorV3Interface.decimals.selector), abi.encode(uint8(8)));
  }
}
