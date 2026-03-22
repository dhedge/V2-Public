// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";

import {BackboneSetup} from "test/integration/utils/foundry/BackboneSetup.t.sol";

abstract contract PoolPrivacyTestSetup is BackboneSetup {
  PoolLogic private testPool;
  PoolManagerLogic private testPoolManagerLogic;
  address public trader = makeAddr("trader");

  function setUp() public virtual override {
    super.setUp();

    IHasSupportedAsset.Asset[] memory supportedAssets = new IHasSupportedAsset.Asset[](1);
    supportedAssets[0] = IHasSupportedAsset.Asset({asset: usdcData.asset, isDeposit: true});

    vm.prank(manager);
    testPool = PoolLogic(
      poolFactoryProxy.createFund({
        _privatePool: false,
        _manager: manager,
        _managerName: "Manager",
        _fundName: "Test Vault",
        _fundSymbol: "TV",
        _performanceFeeNumerator: 0,
        _managerFeeNumerator: 0,
        _entryFeeNumerator: 0,
        _exitFeeNum: 0,
        _supportedAssets: supportedAssets
      })
    );
    testPoolManagerLogic = PoolManagerLogic(testPool.poolManagerLogic());

    // Set up trader
    vm.prank(manager);
    testPoolManagerLogic.setTrader(trader);
  }

  // ================== POOL PRIVACY MANAGEMENT TESTS ==================

  function test_manager_can_set_pool_private() public {
    assertEq(testPool.privatePool(), false, "Pool should start as public");

    vm.expectEmit(false, false, false, true);
    emit PoolPrivacyUpdated(true);

    vm.prank(manager);
    testPoolManagerLogic.setPoolPrivate(true);

    assertEq(testPool.privatePool(), true, "Pool should be set to private");
  }

  function test_manager_can_set_pool_public() public {
    // First set to private
    vm.prank(manager);
    testPoolManagerLogic.setPoolPrivate(true);
    assertEq(testPool.privatePool(), true, "Pool should be private");

    vm.expectEmit(false, false, false, true);
    emit PoolPrivacyUpdated(false);

    vm.prank(manager);
    testPoolManagerLogic.setPoolPrivate(false);

    assertEq(testPool.privatePool(), false, "Pool should be set to public");
  }

  function test_revert_when_non_manager_tries_to_set_privacy() public {
    vm.prank(investor);
    vm.expectRevert(bytes("only manager or trader enabled"));
    testPoolManagerLogic.setPoolPrivate(true);

    assertEq(testPool.privatePool(), false, "Pool privacy should not have changed");
  }

  function test_revert_when_trader_tries_to_set_privacy_without_permission() public {
    vm.prank(trader);
    vm.expectRevert(bytes("only manager or trader enabled"));
    testPoolManagerLogic.setPoolPrivate(true);

    assertEq(testPool.privatePool(), false, "Pool privacy should not have changed");
  }

  // ================== TRADER PRIVACY PERMISSION TESTS ==================

  function test_manager_can_enable_trader_privacy_change_permission() public {
    assertEq(testPoolManagerLogic.traderPrivacyChangeEnabled(), false, "Trader permission should start disabled");

    vm.expectEmit(false, false, false, true);
    emit TraderPrivacyChangePermissionUpdated(address(testPool), manager, true);

    vm.prank(manager);
    testPoolManagerLogic.setTraderPrivacyChangeEnabled(true);

    assertEq(testPoolManagerLogic.traderPrivacyChangeEnabled(), true, "Trader permission should be enabled");
  }

  function test_manager_can_disable_trader_privacy_change_permission() public {
    // First enable the permission
    vm.prank(manager);
    testPoolManagerLogic.setTraderPrivacyChangeEnabled(true);
    assertEq(testPoolManagerLogic.traderPrivacyChangeEnabled(), true, "Trader permission should be enabled");

    vm.expectEmit(false, false, false, true);
    emit TraderPrivacyChangePermissionUpdated(address(testPool), manager, false);

    vm.prank(manager);
    testPoolManagerLogic.setTraderPrivacyChangeEnabled(false);

    assertEq(testPoolManagerLogic.traderPrivacyChangeEnabled(), false, "Trader permission should be disabled");
  }

  function test_revert_when_non_manager_tries_to_set_trader_privacy_permission() public {
    vm.prank(investor);
    vm.expectRevert(bytes("dh4"));
    testPoolManagerLogic.setTraderPrivacyChangeEnabled(true);

    assertEq(testPoolManagerLogic.traderPrivacyChangeEnabled(), false, "Trader permission should not have changed");

    vm.prank(trader);
    vm.expectRevert(bytes("dh4"));
    testPoolManagerLogic.setTraderPrivacyChangeEnabled(true);

    assertEq(testPoolManagerLogic.traderPrivacyChangeEnabled(), false, "Trader permission should not have changed");
  }

  // ================== TRADER PRIVACY CHANGE TESTS ==================

  function test_trader_can_set_privacy_when_permission_enabled() public {
    // Enable trader permission
    vm.prank(manager);
    testPoolManagerLogic.setTraderPrivacyChangeEnabled(true);

    vm.expectEmit(false, false, false, true);
    emit PoolPrivacyUpdated(true);

    vm.prank(trader);
    testPoolManagerLogic.setPoolPrivate(true);

    assertEq(testPool.privatePool(), true, "Pool should be set to private by trader");
  }

  function test_trader_can_toggle_privacy_when_permission_enabled() public {
    // Enable trader permission
    vm.prank(manager);
    testPoolManagerLogic.setTraderPrivacyChangeEnabled(true);

    // Trader sets to private
    vm.prank(trader);
    testPoolManagerLogic.setPoolPrivate(true);
    assertEq(testPool.privatePool(), true, "Pool should be private");

    // Trader sets back to public
    vm.expectEmit(false, false, false, true);
    emit PoolPrivacyUpdated(false);

    vm.prank(trader);
    testPoolManagerLogic.setPoolPrivate(false);

    assertEq(testPool.privatePool(), false, "Pool should be public");
  }

  function test_trader_loses_privacy_permission_when_disabled() public {
    // Enable trader permission
    vm.prank(manager);
    testPoolManagerLogic.setTraderPrivacyChangeEnabled(true);

    // Trader can change privacy
    vm.prank(trader);
    testPoolManagerLogic.setPoolPrivate(true);
    assertEq(testPool.privatePool(), true, "Pool should be private");

    // Manager disables trader permission
    vm.prank(manager);
    testPoolManagerLogic.setTraderPrivacyChangeEnabled(false);

    // Trader should no longer be able to change privacy
    vm.prank(trader);
    vm.expectRevert(bytes("only manager or trader enabled"));
    testPoolManagerLogic.setPoolPrivate(false);

    assertEq(testPool.privatePool(), true, "Pool should remain private");
  }

  function test_manager_retains_privacy_control_when_trader_permission_enabled() public {
    // Enable trader permission
    vm.prank(manager);
    testPoolManagerLogic.setTraderPrivacyChangeEnabled(true);

    // Manager should still be able to control privacy
    vm.prank(manager);
    testPoolManagerLogic.setPoolPrivate(true);
    assertEq(testPool.privatePool(), true, "Pool should be private");

    vm.prank(manager);
    testPoolManagerLogic.setPoolPrivate(false);
    assertEq(testPool.privatePool(), false, "Pool should be public");
  }

  // ================== POOL LOGIC DIRECT ACCESS TESTS ==================

  function test_revert_when_directly_calling_pool_logic_set_private() public {
    vm.prank(manager);
    vm.expectRevert(bytes("dh31"));
    testPool.setPoolPrivate(true);

    assertEq(testPool.privatePool(), false, "Pool privacy should not have changed");
  }

  function test_revert_when_anyone_directly_calls_pool_logic_set_private() public {
    vm.prank(investor);
    vm.expectRevert(bytes("dh31"));
    testPool.setPoolPrivate(true);

    vm.prank(trader);
    vm.expectRevert(bytes("dh31"));
    testPool.setPoolPrivate(true);

    assertEq(testPool.privatePool(), false, "Pool privacy should not have changed");
  }

  // ================== INTEGRATION TESTS WITH EXISTING PRIVACY FUNCTIONALITY ==================

  function test_deposit_blocked_in_private_pool_set_by_manager() public {
    uint256 depositAmount = 1000e6;

    vm.prank(manager);
    testPoolManagerLogic.setPoolPrivate(true);

    vm.prank(investor);
    vm.expectRevert(bytes("dh7"));
    testPool.deposit(usdcData.asset, depositAmount);
  }

  function test_deposit_blocked_in_private_pool_set_by_trader() public {
    uint256 depositAmount = 1000e6;

    // Enable trader permission and set pool private
    vm.prank(manager);
    testPoolManagerLogic.setTraderPrivacyChangeEnabled(true);

    vm.prank(trader);
    testPoolManagerLogic.setPoolPrivate(true);

    vm.prank(investor);
    vm.expectRevert(bytes("dh7"));
    testPool.deposit(usdcData.asset, depositAmount);
  }

  function test_deposit_allowed_after_pool_made_public_by_trader() public {
    uint256 depositAmount = 1000e6;

    // Set pool private first
    vm.prank(manager);
    testPoolManagerLogic.setPoolPrivate(true);

    // Enable trader permission and set back to public
    vm.prank(manager);
    testPoolManagerLogic.setTraderPrivacyChangeEnabled(true);

    vm.prank(trader);
    testPoolManagerLogic.setPoolPrivate(false);

    // Should now be able to deposit
    uint256 liquidityMinted = _makeDeposit(testPool, investor, usdcData.asset, depositAmount);
    assertGt(liquidityMinted, 0, "Deposit should succeed in public pool");
  }

  // Event definitions for testing
  event PoolPrivacyUpdated(bool isPoolPrivate);
  event TraderPrivacyChangePermissionUpdated(address fundAddress, address manager, bool granted);
}
