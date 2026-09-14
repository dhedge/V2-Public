// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {PoolUnitTestSetup} from "test/unit/PoolUnitTestSetup.t.sol";

/// @notice `PoolManagerLogic` role management, the views the front end reads, and the rule that
/// stops vaults being nested into each other recursively.
contract PoolManagerLogicTest is PoolUnitTestSetup {
  address internal trader = makeAddr("trader");
  address internal newManager = makeAddr("newManager");

  /* ========== ROLES ========== */

  function test_manager_can_appoint_and_remove_a_trader() public {
    vm.startPrank(manager);

    fundManagerLogic.setTrader(trader);
    assertEq(fundManagerLogic.trader(), trader);

    fundManagerLogic.removeTrader();
    assertEq(fundManagerLogic.trader(), address(0));

    vm.stopPrank();
  }

  function test_revert_setTrader_when_not_manager() public {
    vm.prank(investor);
    vm.expectRevert(bytes("dh4"));
    fundManagerLogic.setTrader(trader);
  }

  function test_revert_removeTrader_when_not_manager() public {
    vm.prank(manager);
    fundManagerLogic.setTrader(trader);

    vm.prank(investor);
    vm.expectRevert(bytes("dh4"));
    fundManagerLogic.removeTrader();
  }

  function test_manager_can_hand_over_the_pool() public {
    vm.prank(manager);
    fundManagerLogic.changeManager(newManager, "New Manager");

    assertEq(fundManagerLogic.manager(), newManager);
    assertEq(fundManagerLogic.managerName(), "New Manager");
  }

  function test_revert_changeManager_when_not_manager() public {
    vm.prank(investor);
    vm.expectRevert(bytes("dh4"));
    fundManagerLogic.changeManager(newManager, "New Manager");
  }

  function test_the_outgoing_manager_loses_control_after_handover() public {
    vm.prank(manager);
    fundManagerLogic.changeManager(newManager, "New Manager");

    vm.prank(manager);
    vm.expectRevert(bytes("dh4"));
    fundManagerLogic.setTrader(trader);
  }

  /* ========== VIEWS ========== */

  function test_deposit_assets_are_a_subset_of_supported_assets() public view {
    IHasSupportedAsset.Asset[] memory supportedAssets = fundManagerLogic.getSupportedAssets();
    address[] memory depositAssets = fundManagerLogic.getDepositAssets();

    assertEq(supportedAssets.length, 2);
    assertGe(supportedAssets.length, depositAssets.length);
    assertEq(depositAssets[0], address(usdc));
  }

  function test_a_non_deposit_asset_is_supported_but_not_depositable() public {
    // Re-add WETH as a non-deposit asset.
    IHasSupportedAsset.Asset[] memory assetsToAdd = new IHasSupportedAsset.Asset[](1);
    assetsToAdd[0] = IHasSupportedAsset.Asset({asset: address(weth), isDeposit: false});

    vm.prank(manager);
    fundManagerLogic.changeAssets(assetsToAdd, new address[](0));

    assertTrue(fundManagerLogic.isSupportedAsset(address(weth)));
    assertFalse(fundManagerLogic.isDepositAsset(address(weth)));
    assertEq(fundManagerLogic.getDepositAssets().length, 1);
  }

  function test_fund_composition_reports_one_entry_per_supported_asset() public view {
    (IHasSupportedAsset.Asset[] memory assets, uint256[] memory balances, uint256[] memory rates) = fundManagerLogic
      .getFundComposition();

    uint256 supportedCount = fundManagerLogic.getSupportedAssets().length;
    assertEq(assets.length, supportedCount);
    assertEq(balances.length, supportedCount);
    assertEq(rates.length, supportedCount);
  }

  /* ========== NESTED VAULT RESTRICTION ========== */

  /// @dev A vault that is itself priceable can be held by other vaults. Letting it also hold a
  /// vault would make valuation recursive, so it is refused.
  function test_revert_a_priceable_vault_cannot_hold_another_vault() public {
    address otherFund = _createSecondFund();

    // Both have to be priceable: the asset being added is validated first, and this vault being
    // priceable is what makes nesting recursive.
    vm.startPrank(owner);
    assetHandlerProxy.addAsset({asset: otherFund, assetType: 0, aggregator: usdcPriceFeed});
    assetHandlerProxy.addAsset({asset: address(fund), assetType: 0, aggregator: usdcPriceFeed});
    vm.stopPrank();

    IHasSupportedAsset.Asset[] memory assetsToAdd = new IHasSupportedAsset.Asset[](1);
    assetsToAdd[0] = IHasSupportedAsset.Asset({asset: otherFund, isDeposit: false});

    vm.prank(manager);
    vm.expectRevert("cannot add pool asset");
    fundManagerLogic.changeAssets(assetsToAdd, new address[](0));
  }

  function test_a_vault_that_is_not_priceable_may_hold_another_vault() public {
    address otherFund = _createSecondFund();

    // `fund` was never registered as an asset, so nothing can hold it and nesting is safe.
    vm.prank(owner);
    assetHandlerProxy.addAsset({asset: otherFund, assetType: 0, aggregator: usdcPriceFeed});

    IHasSupportedAsset.Asset[] memory assetsToAdd = new IHasSupportedAsset.Asset[](1);
    assetsToAdd[0] = IHasSupportedAsset.Asset({asset: otherFund, isDeposit: false});

    vm.prank(manager);
    fundManagerLogic.changeAssets(assetsToAdd, new address[](0));

    assertTrue(fundManagerLogic.isSupportedAsset(otherFund));
  }

  function _createSecondFund() internal returns (address otherFund) {
    IHasSupportedAsset.Asset[] memory supportedAssets = new IHasSupportedAsset.Asset[](1);
    supportedAssets[0] = IHasSupportedAsset.Asset({asset: address(usdc), isDeposit: true});

    vm.prank(manager);
    otherFund = poolFactoryProxy.createFund({
      _privatePool: false,
      _manager: manager,
      _managerName: "Manager",
      _fundName: "Other Fund",
      _fundSymbol: "OTH",
      _performanceFeeNumerator: 0,
      _managerFeeNumerator: 0,
      _entryFeeNumerator: 0,
      _exitFeeNum: 0,
      _supportedAssets: supportedAssets
    });
  }
}
