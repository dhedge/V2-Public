// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {PoolLogic} from "contracts/PoolLogic.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {IAggregatorV3Interface} from "contracts/interfaces/IAggregatorV3Interface.sol";
import {PoolUnitTestSetup} from "test/unit/PoolUnitTestSetup.t.sol";

contract PoolMaxPriceAgeTest is PoolUnitTestSetup {
  PoolLogic private testPool;

  function setUp() public override {
    super.setUp();

    IHasSupportedAsset.Asset[] memory supportedAssets = new IHasSupportedAsset.Asset[](1);
    supportedAssets[0] = IHasSupportedAsset.Asset({asset: address(usdc), isDeposit: true});

    vm.prank(manager);
    testPool = PoolLogic(
      poolFactoryProxy.createFund({
        _privatePool: false,
        _manager: manager,
        _managerName: "Manager",
        _fundName: "MaxPriceAge Test Vault",
        _fundSymbol: "MPATV",
        _performanceFeeNumerator: 0,
        _managerFeeNumerator: 0,
        _entryFeeNumerator: 0,
        _exitFeeNum: 0,
        _supportedAssets: supportedAssets
      })
    );
  }

  /// @dev Mock the USDC aggregator to return a price updated at the given timestamp.
  function _mockUsdcPriceAt(uint256 _updatedAt) internal {
    vm.mockCall(
      usdcPriceFeed,
      abi.encodeWithSelector(IAggregatorV3Interface.latestRoundData.selector),
      abi.encode(uint80(0), int256(1e8), uint256(0), _updatedAt, uint80(0))
    );
  }

  // --- assetFloor = 0 ---

  function test_deposit_succeeds_when_asset_has_no_price_floor() public {
    assertEq(assetHandlerProxy.assetMaxPriceAge(address(usdc)), 0);

    // Forkless clock starts near zero; advance it so a 1000s-old price is a real past timestamp.
    skip(1000);
    _mockUsdcPriceAt(block.timestamp - 1000);
    _makeDeposit(testPool, investor, address(usdc), 1e6);
  }

  // --- assetMaxPriceAge > 0 (freshness enforced) ---

  function test_deposit_succeeds_when_price_fresh_within_asset_floor() public {
    vm.prank(owner);
    assetHandlerProxy.setAssetMaxPriceAge(address(usdc), 60);

    _mockUsdcPriceAt(block.timestamp);
    _makeDeposit(testPool, investor, address(usdc), 1e6);
  }

  function test_revert_deposit_when_price_stale_beyond_asset_floor() public {
    uint256 floor = 60;
    vm.prank(owner);
    assetHandlerProxy.setAssetMaxPriceAge(address(usdc), floor);

    _mockUsdcPriceAt(block.timestamp);
    skip(floor + 1);

    deal(address(usdc), investor, 1e6);
    vm.startPrank(investor);
    IERC20(address(usdc)).approve(address(testPool), 1e6);
    vm.expectRevert(bytes("dh37"));
    testPool.deposit(address(usdc), 1e6);
    vm.stopPrank();
  }
}
