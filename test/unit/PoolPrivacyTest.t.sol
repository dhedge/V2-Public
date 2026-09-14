// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {PoolUnitTestSetup} from "test/unit/PoolUnitTestSetup.t.sol";

/// @notice Making a pool private restricts who may be *minted* shares - it is not a transfer
/// restriction and it never traps existing holders. This covers both who may flip the privacy flag
/// (manager, and trader only when granted permission) and what the flag does to deposits, transfers
/// and withdrawals.
contract PoolPrivacyTest is PoolUnitTestSetup {
  uint256 internal constant DEPOSIT_AMOUNT = 42e6;

  address internal trader = makeAddr("trader");

  function setUp() public override {
    super.setUp();

    vm.prank(manager);
    fundManagerLogic.setTrader(trader);
  }

  event PoolPrivacyUpdated(bool isPoolPrivate);
  event TraderPrivacyChangePermissionUpdated(address fundAddress, address manager, bool granted);

  /* ========== MINTING IS GATED ========== */

  function test_revert_deposit_for_a_non_member() public {
    _setPrivate();

    vm.prank(investor);
    vm.expectRevert(bytes("dh7"));
    fund.deposit(address(usdc), DEPOSIT_AMOUNT);
  }

  function test_member_can_deposit() public {
    _setPrivate();

    vm.prank(manager);
    fundManagerLogic.addMember(investor);

    uint256 shares = _deposit(investor, address(usdc), DEPOSIT_AMOUNT);

    assertGt(shares, 0);
    assertEq(fund.balanceOf(investor), shares);
  }

  function test_manager_can_deposit_without_being_added_as_a_member() public {
    _setPrivate();

    uint256 shares = _deposit(manager, address(usdc), DEPOSIT_AMOUNT);

    assertGt(shares, 0);
  }

  /* ========== TRANSFERS ARE NOT GATED ========== */

  function test_shares_can_be_transferred_to_a_member() public {
    uint256 shares = _depositBeforeGoingPrivate();

    vm.prank(manager);
    fundManagerLogic.addMember(otherInvestor);

    vm.prank(investor);
    fund.transfer(otherInvestor, shares / 2);

    assertEq(fund.balanceOf(otherInvestor), shares / 2);
  }

  /// @dev Privacy is mint-whitelisting only, so an existing holder may still move shares to
  /// someone who could not have deposited.
  function test_shares_can_be_transferred_to_a_non_member() public {
    uint256 shares = _depositBeforeGoingPrivate();

    vm.prank(investor);
    fund.transfer(otherInvestor, shares / 2);

    assertEq(fund.balanceOf(otherInvestor), shares / 2);
  }

  function test_revert_transfer_to_the_zero_address_still_reports_the_erc20_error() public {
    uint256 shares = _depositBeforeGoingPrivate();

    // Going private must not turn a plain ERC20 mistake into a privacy error.
    vm.prank(investor);
    vm.expectRevert("ERC20: transfer to the zero address");
    fund.transfer(address(0), shares / 2);
  }

  /* ========== HOLDERS ARE NEVER TRAPPED ========== */

  function test_existing_holder_can_withdraw_after_the_pool_goes_private() public {
    uint256 usdcBalanceBefore = usdc.balanceOf(investor);
    uint256 shares = _depositBeforeGoingPrivate();

    _withdraw(investor, shares);

    assertEq(fund.balanceOf(investor), 0);
    assertEq(usdc.balanceOf(investor), usdcBalanceBefore);
  }

  function test_existing_holder_can_withdraw_after_the_pool_goes_private_with_fees_charged() public {
    _setFees({_managerFeeNumerator: 300, _entryFeeNumerator: 25});

    uint256 shares = _depositBeforeGoingPrivate();

    _withdraw(investor, shares);

    assertEq(fund.balanceOf(investor), 0);
  }

  function test_manager_and_dao_can_redeem_fee_shares_after_the_pool_goes_private() public {
    _setFees({_managerFeeNumerator: 300, _entryFeeNumerator: 25});

    uint256 managerUsdcBefore = usdc.balanceOf(manager);
    uint256 daoUsdcBefore = usdc.balanceOf(dao);

    _depositBeforeGoingPrivate();

    // Fee shares were minted to accounts that are not pool members.
    assertGt(fund.balanceOf(manager), 0);
    assertGt(fund.balanceOf(dao), 0);

    _withdraw(manager, fund.balanceOf(manager));
    _withdraw(dao, fund.balanceOf(dao));

    assertGt(usdc.balanceOf(manager), managerUsdcBefore);
    assertGt(usdc.balanceOf(dao), daoUsdcBefore);
  }

  /* ========== POOL PRIVACY MANAGEMENT ========== */

  function test_manager_can_set_pool_private() public {
    assertEq(fund.privatePool(), false, "Pool should start as public");

    vm.expectEmit(false, false, false, true);
    emit PoolPrivacyUpdated(true);

    vm.prank(manager);
    fundManagerLogic.setPoolPrivate(true);

    assertEq(fund.privatePool(), true, "Pool should be set to private");
  }

  function test_manager_can_set_pool_public() public {
    // First set to private
    vm.prank(manager);
    fundManagerLogic.setPoolPrivate(true);
    assertEq(fund.privatePool(), true, "Pool should be private");

    vm.expectEmit(false, false, false, true);
    emit PoolPrivacyUpdated(false);

    vm.prank(manager);
    fundManagerLogic.setPoolPrivate(false);

    assertEq(fund.privatePool(), false, "Pool should be set to public");
  }

  function test_revert_when_non_manager_tries_to_set_privacy() public {
    vm.prank(investor);
    vm.expectRevert(bytes("only manager or trader enabled"));
    fundManagerLogic.setPoolPrivate(true);

    assertEq(fund.privatePool(), false, "Pool privacy should not have changed");
  }

  function test_revert_when_trader_tries_to_set_privacy_without_permission() public {
    vm.prank(trader);
    vm.expectRevert(bytes("only manager or trader enabled"));
    fundManagerLogic.setPoolPrivate(true);

    assertEq(fund.privatePool(), false, "Pool privacy should not have changed");
  }

  /* ========== TRADER PRIVACY PERMISSION ========== */

  function test_manager_can_enable_trader_privacy_change_permission() public {
    assertEq(fundManagerLogic.traderPrivacyChangeEnabled(), false, "Trader permission should start disabled");

    vm.expectEmit(false, false, false, true);
    emit TraderPrivacyChangePermissionUpdated(address(fund), manager, true);

    vm.prank(manager);
    fundManagerLogic.setTraderPrivacyChangeEnabled(true);

    assertEq(fundManagerLogic.traderPrivacyChangeEnabled(), true, "Trader permission should be enabled");
  }

  function test_manager_can_disable_trader_privacy_change_permission() public {
    // First enable the permission
    vm.prank(manager);
    fundManagerLogic.setTraderPrivacyChangeEnabled(true);
    assertEq(fundManagerLogic.traderPrivacyChangeEnabled(), true, "Trader permission should be enabled");

    vm.expectEmit(false, false, false, true);
    emit TraderPrivacyChangePermissionUpdated(address(fund), manager, false);

    vm.prank(manager);
    fundManagerLogic.setTraderPrivacyChangeEnabled(false);

    assertEq(fundManagerLogic.traderPrivacyChangeEnabled(), false, "Trader permission should be disabled");
  }

  function test_revert_when_non_manager_tries_to_set_trader_privacy_permission() public {
    vm.prank(investor);
    vm.expectRevert(bytes("dh4"));
    fundManagerLogic.setTraderPrivacyChangeEnabled(true);

    assertEq(fundManagerLogic.traderPrivacyChangeEnabled(), false, "Trader permission should not have changed");

    vm.prank(trader);
    vm.expectRevert(bytes("dh4"));
    fundManagerLogic.setTraderPrivacyChangeEnabled(true);

    assertEq(fundManagerLogic.traderPrivacyChangeEnabled(), false, "Trader permission should not have changed");
  }

  /* ========== TRADER PRIVACY CHANGE ========== */

  function test_trader_can_set_privacy_when_permission_enabled() public {
    // Enable trader permission
    vm.prank(manager);
    fundManagerLogic.setTraderPrivacyChangeEnabled(true);

    vm.expectEmit(false, false, false, true);
    emit PoolPrivacyUpdated(true);

    vm.prank(trader);
    fundManagerLogic.setPoolPrivate(true);

    assertEq(fund.privatePool(), true, "Pool should be set to private by trader");
  }

  function test_trader_can_toggle_privacy_when_permission_enabled() public {
    // Enable trader permission
    vm.prank(manager);
    fundManagerLogic.setTraderPrivacyChangeEnabled(true);

    // Trader sets to private
    vm.prank(trader);
    fundManagerLogic.setPoolPrivate(true);
    assertEq(fund.privatePool(), true, "Pool should be private");

    // Trader sets back to public
    vm.expectEmit(false, false, false, true);
    emit PoolPrivacyUpdated(false);

    vm.prank(trader);
    fundManagerLogic.setPoolPrivate(false);

    assertEq(fund.privatePool(), false, "Pool should be public");
  }

  function test_trader_loses_privacy_permission_when_disabled() public {
    // Enable trader permission
    vm.prank(manager);
    fundManagerLogic.setTraderPrivacyChangeEnabled(true);

    // Trader can change privacy
    vm.prank(trader);
    fundManagerLogic.setPoolPrivate(true);
    assertEq(fund.privatePool(), true, "Pool should be private");

    // Manager disables trader permission
    vm.prank(manager);
    fundManagerLogic.setTraderPrivacyChangeEnabled(false);

    // Trader should no longer be able to change privacy
    vm.prank(trader);
    vm.expectRevert(bytes("only manager or trader enabled"));
    fundManagerLogic.setPoolPrivate(false);

    assertEq(fund.privatePool(), true, "Pool should remain private");
  }

  function test_manager_retains_privacy_control_when_trader_permission_enabled() public {
    // Enable trader permission
    vm.prank(manager);
    fundManagerLogic.setTraderPrivacyChangeEnabled(true);

    // Manager should still be able to control privacy
    vm.prank(manager);
    fundManagerLogic.setPoolPrivate(true);
    assertEq(fund.privatePool(), true, "Pool should be private");

    vm.prank(manager);
    fundManagerLogic.setPoolPrivate(false);
    assertEq(fund.privatePool(), false, "Pool should be public");
  }

  /* ========== POOL LOGIC DIRECT ACCESS ========== */

  function test_revert_when_directly_calling_pool_logic_set_private() public {
    vm.prank(manager);
    vm.expectRevert(bytes("dh31"));
    fund.setPoolPrivate(true);

    assertEq(fund.privatePool(), false, "Pool privacy should not have changed");
  }

  function test_revert_when_anyone_directly_calls_pool_logic_set_private() public {
    vm.prank(investor);
    vm.expectRevert(bytes("dh31"));
    fund.setPoolPrivate(true);

    vm.prank(trader);
    vm.expectRevert(bytes("dh31"));
    fund.setPoolPrivate(true);

    assertEq(fund.privatePool(), false, "Pool privacy should not have changed");
  }

  /* ========== HELPERS ========== */

  function _setPrivate() internal {
    vm.prank(manager);
    fundManagerLogic.setPoolPrivate(true);
  }

  /// @dev Deposits while the pool is still public, clears the lockup, then makes it private - the
  /// position an existing holder is in when a manager closes the pool.
  function _depositBeforeGoingPrivate() internal returns (uint256 shares) {
    shares = _deposit(investor, address(usdc), DEPOSIT_AMOUNT);
    vm.warp(block.timestamp + EXIT_COOLDOWN + 1);
    _setPrivate();
  }

  function _setFees(uint256 _managerFeeNumerator, uint256 _entryFeeNumerator) internal {
    vm.prank(manager);
    fundManagerLogic.announceFeeIncrease(0, _managerFeeNumerator, _entryFeeNumerator, 0);

    vm.warp(block.timestamp + 4 weeks);

    vm.prank(manager);
    fundManagerLogic.commitFeeIncrease();
  }
}
