// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {ERC20Asset} from "contracts/test/TestAssets.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {PoolUnitTestSetup} from "test/unit/PoolUnitTestSetup.t.sol";

/// @notice The rules governing a vault's supported asset list: what may be added, what may be
/// removed, and the invariants that hold throughout (a cap on how many, and always at least one
/// asset that can be deposited).
contract PoolAssetManagementTest is PoolUnitTestSetup {
  ERC20Asset internal extraAsset;

  function setUp() public override {
    super.setUp();

    extraAsset = new ERC20Asset("Extra", "EXTRA");

    vm.prank(owner);
    assetHandlerProxy.addAsset({asset: address(extraAsset), assetType: 0, aggregator: usdcPriceFeed});
  }

  /* ========== ADDING ========== */

  function test_manager_can_add_a_supported_asset() public {
    _addAsset(address(extraAsset), false);

    assertEq(fundManagerLogic.getSupportedAssets().length, 3);
    assertTrue(fundManagerLogic.isSupportedAsset(address(extraAsset)));
    assertFalse(fundManagerLogic.isDepositAsset(address(extraAsset)));
  }

  function test_revert_adding_an_asset_the_handler_does_not_know() public {
    address unknownAsset = address(new ERC20Asset("Unknown", "UNK"));

    IHasSupportedAsset.Asset[] memory assetsToAdd = new IHasSupportedAsset.Asset[](1);
    assetsToAdd[0] = IHasSupportedAsset.Asset({asset: unknownAsset, isDeposit: false});

    vm.prank(manager);
    vm.expectRevert("invalid asset");
    fundManagerLogic.changeAssets(assetsToAdd, new address[](0));
  }

  function test_revert_adding_beyond_the_supported_asset_cap() public {
    uint256 cap = poolFactoryProxy.getMaximumSupportedAssetCount();
    uint256 alreadySupported = fundManagerLogic.getSupportedAssets().length;

    // Fill exactly to the cap, then one more.
    _addFillerAssets(cap - alreadySupported);
    assertEq(fundManagerLogic.getSupportedAssets().length, cap);

    IHasSupportedAsset.Asset[] memory oneTooMany = new IHasSupportedAsset.Asset[](1);
    oneTooMany[0] = IHasSupportedAsset.Asset({asset: address(extraAsset), isDeposit: false});

    vm.prank(manager);
    vm.expectRevert("maximum assets reached");
    fundManagerLogic.changeAssets(oneTooMany, new address[](0));
  }

  function test_room_frees_up_again_once_an_asset_is_removed() public {
    uint256 cap = poolFactoryProxy.getMaximumSupportedAssetCount();
    address[] memory fillers = _addFillerAssets(cap - fundManagerLogic.getSupportedAssets().length);

    vm.startPrank(manager);
    fundManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), _toArray(fillers[0]));

    IHasSupportedAsset.Asset[] memory assetsToAdd = new IHasSupportedAsset.Asset[](1);
    assetsToAdd[0] = IHasSupportedAsset.Asset({asset: address(extraAsset), isDeposit: false});
    fundManagerLogic.changeAssets(assetsToAdd, new address[](0));
    vm.stopPrank();

    assertEq(fundManagerLogic.getSupportedAssets().length, cap);
    assertTrue(fundManagerLogic.isSupportedAsset(address(extraAsset)));
  }

  /* ========== REMOVING ========== */

  function test_manager_can_remove_an_empty_asset() public {
    _addAsset(address(extraAsset), false);

    vm.prank(manager);
    fundManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), _toArray(address(extraAsset)));

    assertFalse(fundManagerLogic.isSupportedAsset(address(extraAsset)));
  }

  function test_revert_removing_an_asset_the_vault_still_holds() public {
    _addAsset(address(extraAsset), false);
    extraAsset.transfer(address(fund), 1);

    vm.prank(manager);
    vm.expectRevert("cannot remove non-empty asset");
    fundManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), _toArray(address(extraAsset)));
  }

  function test_revert_removing_an_asset_the_vault_does_not_support() public {
    vm.prank(manager);
    vm.expectRevert("asset not supported");
    fundManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), _toArray(address(extraAsset)));
  }

  /// @dev A vault must always keep somewhere for money to come in, so the last deposit asset is
  /// not removable.
  function test_revert_removing_the_last_deposit_asset() public {
    // WETH is the only other deposit asset; drop it first so USDC stands alone.
    vm.startPrank(manager);
    fundManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), _toArray(address(weth)));

    vm.expectRevert("at least one deposit asset");
    fundManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), _toArray(address(usdc)));
    vm.stopPrank();
  }

  /* ========== DEPOSIT FLAG ========== */

  function test_manager_can_turn_an_asset_into_a_deposit_asset() public {
    _addAsset(address(extraAsset), false);
    assertFalse(fundManagerLogic.isDepositAsset(address(extraAsset)));

    _addAsset(address(extraAsset), true);

    assertTrue(fundManagerLogic.isDepositAsset(address(extraAsset)));
    // Re-adding does not duplicate the entry.
    assertEq(fundManagerLogic.getSupportedAssets().length, 3);
  }

  function test_manager_can_stop_an_asset_being_depositable_without_removing_it() public {
    _addAsset(address(weth), false);

    assertTrue(fundManagerLogic.isSupportedAsset(address(weth)));
    assertFalse(fundManagerLogic.isDepositAsset(address(weth)));
  }

  function test_revert_turning_off_the_last_deposit_asset() public {
    vm.startPrank(manager);
    fundManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), _toArray(address(weth)));

    IHasSupportedAsset.Asset[] memory assetsToAdd = new IHasSupportedAsset.Asset[](1);
    assetsToAdd[0] = IHasSupportedAsset.Asset({asset: address(usdc), isDeposit: false});

    vm.expectRevert("at least one deposit asset");
    fundManagerLogic.changeAssets(assetsToAdd, new address[](0));
    vm.stopPrank();
  }

  /* ========== HELPERS ========== */

  function _addAsset(address _asset, bool _isDeposit) internal {
    IHasSupportedAsset.Asset[] memory assetsToAdd = new IHasSupportedAsset.Asset[](1);
    assetsToAdd[0] = IHasSupportedAsset.Asset({asset: _asset, isDeposit: _isDeposit});

    vm.prank(manager);
    fundManagerLogic.changeAssets(assetsToAdd, new address[](0));
  }

  function _addFillerAssets(uint256 _count) internal returns (address[] memory fillers) {
    fillers = new address[](_count);
    IHasSupportedAsset.Asset[] memory assetsToAdd = new IHasSupportedAsset.Asset[](_count);

    for (uint256 i; i < _count; ++i) {
      address filler = address(new ERC20Asset("Filler", "FILL"));
      fillers[i] = filler;
      assetsToAdd[i] = IHasSupportedAsset.Asset({asset: filler, isDeposit: false});

      vm.prank(owner);
      assetHandlerProxy.addAsset({asset: filler, assetType: 0, aggregator: usdcPriceFeed});
    }

    vm.prank(manager);
    fundManagerLogic.changeAssets(assetsToAdd, new address[](0));
  }
}
