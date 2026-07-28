// SPDX-License-Identifier: MIT
// solhint-disable one-contract-per-file
pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import {PoolLogic} from "contracts/PoolLogic.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/TransparentUpgradeableProxy.sol";

import {BackboneSetup} from "test/integration/utils/foundry/BackboneSetup.t.sol";

/// @dev Local mirror of the `WithdrawalGuardian` (0.8.28) ABI. This test file compiles as 0.7.6 because
///      it imports `PoolLogic` (pinned to 0.7.6), so it cannot import the 0.8.28 contract directly. The
///      implementation is deployed via `deployCode` and driven through this interface.
interface IWithdrawalGuardian {
  enum WithdrawalPhase {
    None,
    Idle,
    Pending,
    Unlockable,
    Expired
  }

  struct DepositorView {
    WithdrawalPhase phase;
    uint256 lockedBalance;
    uint256 requestTime;
    uint256 unlockWindowStart;
    uint256 unlockWindowEnd;
    uint256 secondsUntilUnlock;
    uint256 secondsUntilExpiry;
    bool earlyApproved;
    uint256 earlyApprovalExpiry;
    address recoveryDestination;
    uint256 recoveryExpiry;
    uint256 withdrawalDelay;
  }

  function initialize(address poolFactory_, uint256 withdrawalDelay_) external;

  function withdrawalDelay() external view returns (uint256);

  function poolFactory() external view returns (address);

  function setWithdrawalDelay(uint256 newDelay_) external;

  function lock(address pool, uint256 amount) external;

  function requestWithdrawal(address pool) external;

  function unlock(address pool, uint256 amount) external;

  function approveWithdrawal(address pool, address depositor) external;

  function approveRecoveryTransfer(address pool, address depositor, address safeAddress) external;

  function executeRecovery(address pool) external;

  function getDepositorView(address pool, address depositor) external view returns (DepositorView memory);

  function getDepositorPositions(
    address depositor
  ) external view returns (address[] memory pools, DepositorView[] memory views);

  function getPendingApprovals(
    address pool
  ) external view returns (address[] memory depositors, DepositorView[] memory views);
}

/// @title WithdrawalGuardianTestSetup
/// @notice Chain-agnostic test suite for `WithdrawalGuardian`: exhaustive revert checks plus a full walk
///         of the lock -> request -> unlock / approve / recover state machine. Concrete per-chain
///         contracts (e.g. base/core) supply the fork.
abstract contract WithdrawalGuardianTestSetup is BackboneSetup {
  // Events mirrored from `WithdrawalGuardian` for `vm.expectEmit`.
  event Locked(address indexed pool, address indexed depositor, uint256 amount);
  event WithdrawalRequested(address indexed pool, address indexed depositor, uint64 unlockTime);
  event Unlocked(address indexed pool, address indexed depositor, uint256 amount);
  event WithdrawalApproved(address indexed pool, address indexed depositor, address approver, uint64 validUntil);
  event RecoveryTransferApproved(
    address indexed pool,
    address indexed depositor,
    address newAddress,
    address approver,
    uint64 validUntil
  );
  event RecoveryExecuted(address indexed pool, address indexed depositor, address recipient, uint256 amount);
  event WithdrawalDelaySet(uint256 delay);

  uint256 internal constant MIN_DELAY = 24 hours;
  uint256 internal constant MAX_DELAY = 30 days;
  uint256 internal constant WITHDRAWAL_DELAY = 3 days; // > 1-day pool exit cooldown, so recovery windows stay clean
  uint256 internal constant DEPOSIT_AMOUNT = 1_000e6; // USDC has 6 decimals

  address internal guardianImpl;
  IWithdrawalGuardian internal guardian;
  PoolLogic internal pool;
  uint256 internal investorTokens;

  address internal safe = makeAddr("safe");
  address internal attacker = makeAddr("attacker");
  address internal stranger = makeAddr("stranger");
  address internal depositorB = makeAddr("depositorB");

  function setUp() public virtual override {
    super.setUp();

    vm.startPrank(owner);
    guardianImpl = deployCode("WithdrawalGuardian.sol");
    bytes memory initData = abi.encodeWithSelector(
      IWithdrawalGuardian.initialize.selector,
      address(poolFactoryProxy),
      WITHDRAWAL_DELAY
    );
    guardian = IWithdrawalGuardian(address(new TransparentUpgradeableProxy(guardianImpl, proxyAdmin, initData)));
    // Required so depositors can move pool tokens into the guardian without tripping the exit cooldown.
    poolFactoryProxy.addReceiverWhitelist(address(guardian));
    vm.stopPrank();

    pool = _createUsdcPool("Time-Locked Vault", "TLV");
    investorTokens = _makeDeposit(pool, investor, usdcData.asset, DEPOSIT_AMOUNT);
  }

  ////////////////////////////////
  //          Helpers           //
  ////////////////////////////////

  function _createUsdcPool(string memory name, string memory symbol) internal returns (PoolLogic newPool) {
    IHasSupportedAsset.Asset[] memory supportedAssets = new IHasSupportedAsset.Asset[](1);
    supportedAssets[0] = IHasSupportedAsset.Asset({asset: usdcData.asset, isDeposit: true});

    vm.prank(manager);
    newPool = PoolLogic(
      poolFactoryProxy.createFund(false, manager, "Manager", name, symbol, 0, 0, 0, 0, supportedAssets)
    );
  }

  function _lock(address depositor, PoolLogic targetPool, uint256 amount) internal {
    vm.startPrank(depositor);
    targetPool.approve(address(guardian), amount);
    guardian.lock(address(targetPool), amount);
    vm.stopPrank();
  }

  function _request(address depositor, PoolLogic targetPool) internal returns (uint256 requestTime) {
    vm.prank(depositor);
    guardian.requestWithdrawal(address(targetPool));
    requestTime = block.timestamp;
  }

  function _lockAndRequest(
    address depositor,
    PoolLogic targetPool,
    uint256 amount
  ) internal returns (uint256 requestTime) {
    _lock(depositor, targetPool, amount);
    requestTime = _request(depositor, targetPool);
  }

  function _contains(address[] memory arr, address target) internal pure returns (bool) {
    for (uint256 i; i < arr.length; ++i) {
      if (arr[i] == target) return true;
    }
    return false;
  }

  ////////////////////////////////
  //   initialize reverts       //
  ////////////////////////////////

  function test_revert_initialize_zero_factory() public {
    IWithdrawalGuardian fresh = IWithdrawalGuardian(
      address(new TransparentUpgradeableProxy(guardianImpl, proxyAdmin, ""))
    );

    vm.expectRevert(abi.encodeWithSignature("ZeroAddress(string)", "poolFactory"));
    fresh.initialize(address(0), WITHDRAWAL_DELAY);
  }

  function test_revert_initialize_delay_below_min() public {
    IWithdrawalGuardian fresh = IWithdrawalGuardian(
      address(new TransparentUpgradeableProxy(guardianImpl, proxyAdmin, ""))
    );

    vm.expectRevert(abi.encodeWithSignature("InvalidDelay(uint256)", MIN_DELAY - 1));
    fresh.initialize(address(poolFactoryProxy), MIN_DELAY - 1);
  }

  function test_revert_initialize_delay_above_max() public {
    IWithdrawalGuardian fresh = IWithdrawalGuardian(
      address(new TransparentUpgradeableProxy(guardianImpl, proxyAdmin, ""))
    );

    vm.expectRevert(abi.encodeWithSignature("InvalidDelay(uint256)", MAX_DELAY + 1));
    fresh.initialize(address(poolFactoryProxy), MAX_DELAY + 1);
  }

  function test_revert_initialize_twice() public {
    vm.expectRevert(abi.encodeWithSignature("InvalidInitialization()"));
    guardian.initialize(address(poolFactoryProxy), WITHDRAWAL_DELAY);
  }

  ////////////////////////////////
  //  setWithdrawalDelay reverts //
  ////////////////////////////////

  function test_revert_setWithdrawalDelay_not_owner() public {
    vm.expectRevert(abi.encodeWithSignature("UnauthorizedCaller(address)", stranger));
    vm.prank(stranger);
    guardian.setWithdrawalDelay(2 days);
  }

  function test_revert_setWithdrawalDelay_below_min() public {
    vm.expectRevert(abi.encodeWithSignature("InvalidDelay(uint256)", MIN_DELAY - 1));
    vm.prank(owner);
    guardian.setWithdrawalDelay(MIN_DELAY - 1);
  }

  function test_revert_setWithdrawalDelay_above_max() public {
    vm.expectRevert(abi.encodeWithSignature("InvalidDelay(uint256)", MAX_DELAY + 1));
    vm.prank(owner);
    guardian.setWithdrawalDelay(MAX_DELAY + 1);
  }

  ////////////////////////////////
  //       lock reverts          //
  ////////////////////////////////

  function test_revert_lock_invalid_pool() public {
    address badPool = makeAddr("badPool");
    vm.expectRevert(abi.encodeWithSignature("InvalidPool(address)", badPool));
    vm.prank(investor);
    guardian.lock(badPool, 1);
  }

  function test_revert_lock_zero_amount() public {
    vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
    vm.prank(investor);
    guardian.lock(address(pool), 0);
  }

  ////////////////////////////////
  //  requestWithdrawal reverts  //
  ////////////////////////////////

  function test_revert_requestWithdrawal_invalid_pool() public {
    address badPool = makeAddr("badPool");
    vm.expectRevert(abi.encodeWithSignature("InvalidPool(address)", badPool));
    vm.prank(investor);
    guardian.requestWithdrawal(badPool);
  }

  function test_revert_requestWithdrawal_nothing_locked() public {
    vm.expectRevert(abi.encodeWithSignature("NothingLocked()"));
    vm.prank(investor);
    guardian.requestWithdrawal(address(pool));
  }

  ////////////////////////////////
  //      unlock reverts         //
  ////////////////////////////////

  function test_revert_unlock_invalid_pool() public {
    address badPool = makeAddr("badPool");
    vm.expectRevert(abi.encodeWithSignature("InvalidPool(address)", badPool));
    vm.prank(investor);
    guardian.unlock(badPool, 1);
  }

  function test_revert_unlock_zero_amount() public {
    _lock(investor, pool, investorTokens);
    vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
    vm.prank(investor);
    guardian.unlock(address(pool), 0);
  }

  function test_revert_unlock_insufficient_locked_balance() public {
    _lock(investor, pool, investorTokens);
    vm.expectRevert(abi.encodeWithSignature("InsufficientLockedBalance()"));
    vm.prank(investor);
    guardian.unlock(address(pool), investorTokens + 1);
  }

  function test_revert_unlock_locked_when_idle() public {
    _lock(investor, pool, investorTokens); // locked, never requested
    vm.expectRevert(abi.encodeWithSignature("WithdrawalLocked()"));
    vm.prank(investor);
    guardian.unlock(address(pool), investorTokens);
  }

  function test_revert_unlock_locked_before_window() public {
    uint256 reqTime = _lockAndRequest(investor, pool, investorTokens);
    vm.warp(reqTime + WITHDRAWAL_DELAY - 1);
    vm.expectRevert(abi.encodeWithSignature("WithdrawalLocked()"));
    vm.prank(investor);
    guardian.unlock(address(pool), investorTokens);
  }

  function test_revert_unlock_locked_after_window_expired() public {
    uint256 reqTime = _lockAndRequest(investor, pool, investorTokens);
    vm.warp(reqTime + 2 * WITHDRAWAL_DELAY); // window lapsed
    vm.expectRevert(abi.encodeWithSignature("WithdrawalLocked()"));
    vm.prank(investor);
    guardian.unlock(address(pool), investorTokens);
  }

  ////////////////////////////////
  //  approveWithdrawal reverts  //
  ////////////////////////////////

  function test_revert_approveWithdrawal_invalid_pool() public {
    address badPool = makeAddr("badPool");
    vm.expectRevert(abi.encodeWithSignature("InvalidPool(address)", badPool));
    vm.prank(manager);
    guardian.approveWithdrawal(badPool, investor);
  }

  function test_revert_approveWithdrawal_unauthorized() public {
    vm.expectRevert(abi.encodeWithSignature("UnauthorizedCaller(address)", stranger));
    vm.prank(stranger);
    guardian.approveWithdrawal(address(pool), investor);
  }

  function test_revert_approveWithdrawal_no_pending_request() public {
    _lock(investor, pool, investorTokens); // locked but no request
    vm.expectRevert(abi.encodeWithSignature("NoPendingRequest()"));
    vm.prank(manager);
    guardian.approveWithdrawal(address(pool), investor);
  }

  function test_revert_approveWithdrawal_stale_expired_request() public {
    uint256 reqTime = _lockAndRequest(investor, pool, investorTokens);
    vm.warp(reqTime + 2 * WITHDRAWAL_DELAY); // window lapsed -> Expired

    // A manager must not be able to revive a long-forgotten (expired) request into an early unlock.
    vm.expectRevert(abi.encodeWithSignature("NoPendingRequest()"));
    vm.prank(manager);
    guardian.approveWithdrawal(address(pool), investor);
  }

  ////////////////////////////////
  // approveRecoveryTransfer reverts //
  ////////////////////////////////

  function test_revert_approveRecoveryTransfer_invalid_pool() public {
    address badPool = makeAddr("badPool");
    vm.expectRevert(abi.encodeWithSignature("InvalidPool(address)", badPool));
    vm.prank(manager);
    guardian.approveRecoveryTransfer(badPool, investor, safe);
  }

  function test_revert_approveRecoveryTransfer_unauthorized() public {
    vm.expectRevert(abi.encodeWithSignature("UnauthorizedCaller(address)", stranger));
    vm.prank(stranger);
    guardian.approveRecoveryTransfer(address(pool), investor, safe);
  }

  function test_revert_approveRecoveryTransfer_zero_safe_address() public {
    vm.expectRevert(abi.encodeWithSignature("ZeroAddress(string)", "safeAddress"));
    vm.prank(manager);
    guardian.approveRecoveryTransfer(address(pool), investor, address(0));
  }

  function test_revert_approveRecoveryTransfer_no_pending_request() public {
    _lock(investor, pool, investorTokens); // locked but no request
    vm.expectRevert(abi.encodeWithSignature("NoPendingRequest()"));
    vm.prank(manager);
    guardian.approveRecoveryTransfer(address(pool), investor, safe);
  }

  ////////////////////////////////
  //   executeRecovery reverts   //
  ////////////////////////////////

  function test_revert_executeRecovery_invalid_pool() public {
    address badPool = makeAddr("badPool");
    vm.expectRevert(abi.encodeWithSignature("InvalidPool(address)", badPool));
    vm.prank(investor);
    guardian.executeRecovery(badPool);
  }

  function test_revert_executeRecovery_no_recovery_approved() public {
    _lockAndRequest(investor, pool, investorTokens); // requested, but no recovery approval
    vm.expectRevert(abi.encodeWithSignature("NoRecoveryApproved()"));
    vm.prank(investor);
    guardian.executeRecovery(address(pool));
  }

  function test_revert_executeRecovery_when_approval_expired() public {
    uint256 reqTime = _lockAndRequest(investor, pool, investorTokens);
    vm.prank(manager);
    guardian.approveRecoveryTransfer(address(pool), investor, safe);

    vm.warp(reqTime + WITHDRAWAL_DELAY); // recoveryExpiry == reqTime + delay
    vm.expectRevert(abi.encodeWithSignature("NoRecoveryApproved()"));
    vm.prank(investor);
    guardian.executeRecovery(address(pool));
  }

  function test_revert_executeRecovery_non_depositor_caller() public {
    // Manager approves recovery for the investor; an attacker cannot trigger it (their own state is empty).
    _lockAndRequest(investor, pool, investorTokens);
    vm.prank(manager);
    guardian.approveRecoveryTransfer(address(pool), investor, safe);

    vm.expectRevert(abi.encodeWithSignature("NoRecoveryApproved()"));
    vm.prank(attacker);
    guardian.executeRecovery(address(pool));
  }

  ////////////////////////////////
  //     pool cooldown guard     //
  ////////////////////////////////

  /// @dev A guardian round-trip (lock -> request -> manager early-approve -> unlock back to self) must not
  ///      reset the depositor's pool exit cooldown. The tokens return to the same address, which still
  ///      carries its original cooldown, so an immediate pool withdraw reverts with "dh3".
  function test_unlock_to_self_does_not_bypass_pool_cooldown() public {
    // Investor deposited in setUp and is still within the pool's 1-day exit cooldown.
    _lockAndRequest(investor, pool, investorTokens);
    vm.prank(manager);
    guardian.approveWithdrawal(address(pool), investor);
    vm.prank(investor);
    guardian.unlock(address(pool), investorTokens);

    // Move past the same-block guard ("dh11") but stay well within the 1-day cooldown.
    vm.warp(block.timestamp + 1 hours);
    assertGt(pool.getExitRemainingCooldown(investor), 0, "pool cooldown still active");

    // The round-trip did not clear the depositor's pool cooldown: withdraw still reverts "dh3".
    vm.expectRevert(bytes("dh3"));
    vm.prank(investor);
    pool.withdraw(investorTokens);
  }

  /// @dev Recovery routes tokens to a fresh (zero-cooldown) safe address. While the depositor is still in
  ///      the pool exit cooldown, `executeRecovery` must revert so it cannot be used to escape that cooldown.
  function test_executeRecovery_reverts_while_pool_cooldown_active() public {
    _lockAndRequest(investor, pool, investorTokens);
    vm.prank(manager);
    guardian.approveRecoveryTransfer(address(pool), investor, safe);

    assertGt(pool.getExitRemainingCooldown(investor), 0, "pool cooldown still active");

    vm.expectRevert(abi.encodeWithSignature("WithdrawalLocked()"));
    vm.prank(investor);
    guardian.executeRecovery(address(pool));

    // The guard is scoped to the cooldown only: once it elapses (recovery approval still valid), it works.
    vm.warp(block.timestamp + 1 days + 1);
    assertEq(pool.getExitRemainingCooldown(investor), 0, "pool cooldown elapsed");
    vm.prank(investor);
    guardian.executeRecovery(address(pool));
    assertEq(pool.balanceOf(safe), investorTokens, "recovered to safe after cooldown");
  }

  ////////////////////////////////
  //     state machine flow      //
  ////////////////////////////////

  function test_getDepositorView_empty_is_none() public view {
    IWithdrawalGuardian.DepositorView memory v = guardian.getDepositorView(address(pool), stranger);
    assertEq(uint256(v.phase), uint256(IWithdrawalGuardian.WithdrawalPhase.None), "phase None");
    assertEq(v.lockedBalance, 0, "no balance");
    assertEq(v.withdrawalDelay, WITHDRAWAL_DELAY, "delay still reported");
  }

  function test_lock_sets_idle_phase_and_tracks_position() public {
    uint256 lockAmount = investorTokens / 2;

    vm.startPrank(investor);
    pool.approve(address(guardian), lockAmount);
    vm.expectEmit(true, true, false, true, address(guardian));
    emit Locked(address(pool), investor, lockAmount);
    guardian.lock(address(pool), lockAmount);
    vm.stopPrank();

    assertEq(pool.balanceOf(address(guardian)), lockAmount, "guardian custody balance");

    IWithdrawalGuardian.DepositorView memory v = guardian.getDepositorView(address(pool), investor);
    assertEq(uint256(v.phase), uint256(IWithdrawalGuardian.WithdrawalPhase.Idle), "phase Idle");
    assertEq(v.lockedBalance, lockAmount, "locked balance");
    assertEq(v.requestTime, 0, "no pending request");
    assertEq(v.withdrawalDelay, WITHDRAWAL_DELAY, "delay snapshot");

    (address[] memory pools, IWithdrawalGuardian.DepositorView[] memory views) = guardian.getDepositorPositions(
      investor
    );
    assertEq(pools.length, 1, "one position");
    assertEq(pools[0], address(pool), "position pool");
    assertEq(views[0].lockedBalance, lockAmount, "position balance");
  }

  function test_requestWithdrawal_opens_pending_window() public {
    _lock(investor, pool, investorTokens);

    uint64 expectedUnlock = uint64(block.timestamp + WITHDRAWAL_DELAY);
    vm.expectEmit(true, true, false, true, address(guardian));
    emit WithdrawalRequested(address(pool), investor, expectedUnlock);
    vm.prank(investor);
    guardian.requestWithdrawal(address(pool));

    uint256 reqTime = block.timestamp;
    IWithdrawalGuardian.DepositorView memory v = guardian.getDepositorView(address(pool), investor);
    assertEq(uint256(v.phase), uint256(IWithdrawalGuardian.WithdrawalPhase.Pending), "phase Pending");
    assertEq(v.requestTime, reqTime, "request time");
    assertEq(v.unlockWindowStart, reqTime + WITHDRAWAL_DELAY, "window start");
    assertEq(v.unlockWindowEnd, reqTime + 2 * WITHDRAWAL_DELAY, "window end");
    assertEq(v.secondsUntilUnlock, WITHDRAWAL_DELAY, "seconds until unlock");

    (address[] memory depositors, ) = guardian.getPendingApprovals(address(pool));
    assertEq(depositors.length, 1, "one pending request");
    assertEq(depositors[0], investor, "pending depositor");
  }

  function test_phase_becomes_unlockable_within_window() public {
    uint256 reqTime = _lockAndRequest(investor, pool, investorTokens);
    vm.warp(reqTime + WITHDRAWAL_DELAY);

    IWithdrawalGuardian.DepositorView memory v = guardian.getDepositorView(address(pool), investor);
    assertEq(uint256(v.phase), uint256(IWithdrawalGuardian.WithdrawalPhase.Unlockable), "phase Unlockable");
    assertEq(v.secondsUntilUnlock, 0, "no countdown remaining");
    assertEq(v.secondsUntilExpiry, WITHDRAWAL_DELAY, "full window left to act");
  }

  function test_unlock_full_returns_tokens_and_clears_state() public {
    uint256 reqTime = _lockAndRequest(investor, pool, investorTokens);
    vm.warp(reqTime + WITHDRAWAL_DELAY);

    uint256 balBefore = pool.balanceOf(investor);

    vm.expectEmit(true, true, false, true, address(guardian));
    emit Unlocked(address(pool), investor, investorTokens);
    vm.prank(investor);
    guardian.unlock(address(pool), investorTokens);

    assertEq(pool.balanceOf(investor), balBefore + investorTokens, "tokens returned");
    assertEq(pool.balanceOf(address(guardian)), 0, "guardian emptied");

    IWithdrawalGuardian.DepositorView memory v = guardian.getDepositorView(address(pool), investor);
    assertEq(uint256(v.phase), uint256(IWithdrawalGuardian.WithdrawalPhase.None), "phase None");
    assertEq(v.lockedBalance, 0, "no balance left");

    (address[] memory pools, ) = guardian.getDepositorPositions(investor);
    assertEq(pools.length, 0, "position removed");
    (address[] memory depositors, ) = guardian.getPendingApprovals(address(pool));
    assertEq(depositors.length, 0, "no pending request");
  }

  function test_unlock_partial_resets_cycle_to_idle() public {
    uint256 half = investorTokens / 2;
    uint256 reqTime = _lockAndRequest(investor, pool, investorTokens);
    vm.warp(reqTime + WITHDRAWAL_DELAY);

    vm.prank(investor);
    guardian.unlock(address(pool), half);

    IWithdrawalGuardian.DepositorView memory v = guardian.getDepositorView(address(pool), investor);
    assertEq(uint256(v.phase), uint256(IWithdrawalGuardian.WithdrawalPhase.Idle), "cycle reset to Idle");
    assertEq(v.lockedBalance, investorTokens - half, "remaining balance");
    assertEq(v.requestTime, 0, "request cleared");

    (address[] memory pools, ) = guardian.getDepositorPositions(investor);
    assertEq(pools.length, 1, "still holds a position");
    (address[] memory depositors, ) = guardian.getPendingApprovals(address(pool));
    assertEq(depositors.length, 0, "no longer pending");

    // The remaining balance is re-locked and needs a fresh matured request.
    vm.expectRevert(abi.encodeWithSignature("WithdrawalLocked()"));
    vm.prank(investor);
    guardian.unlock(address(pool), investorTokens - half);
  }

  function test_unlock_window_lower_boundary() public {
    uint256 reqTime = _lockAndRequest(investor, pool, investorTokens);

    // One second before the window opens: still locked.
    vm.warp(reqTime + WITHDRAWAL_DELAY - 1);
    vm.expectRevert(abi.encodeWithSignature("WithdrawalLocked()"));
    vm.prank(investor);
    guardian.unlock(address(pool), investorTokens);

    // Exactly at window open: succeeds.
    vm.warp(reqTime + WITHDRAWAL_DELAY);
    vm.prank(investor);
    guardian.unlock(address(pool), investorTokens);
    assertEq(pool.balanceOf(address(guardian)), 0, "unlocked at lower boundary");
  }

  function test_unlock_window_upper_boundary() public {
    uint256 reqTime = _lockAndRequest(investor, pool, investorTokens);

    // Last valid second of the window.
    vm.warp(reqTime + 2 * WITHDRAWAL_DELAY - 1);
    IWithdrawalGuardian.DepositorView memory v = guardian.getDepositorView(address(pool), investor);
    assertEq(uint256(v.phase), uint256(IWithdrawalGuardian.WithdrawalPhase.Unlockable), "still unlockable");

    vm.prank(investor);
    guardian.unlock(address(pool), investorTokens);
    assertEq(pool.balanceOf(address(guardian)), 0, "unlocked at upper boundary");
  }

  function test_expired_request_can_be_reopened() public {
    uint256 reqTime = _lockAndRequest(investor, pool, investorTokens);
    vm.warp(reqTime + 2 * WITHDRAWAL_DELAY); // window lapsed -> Expired

    IWithdrawalGuardian.DepositorView memory v = guardian.getDepositorView(address(pool), investor);
    assertEq(uint256(v.phase), uint256(IWithdrawalGuardian.WithdrawalPhase.Expired), "phase Expired");

    uint256 newReq = _request(investor, pool);
    vm.warp(newReq + WITHDRAWAL_DELAY);
    vm.prank(investor);
    guardian.unlock(address(pool), investorTokens);
    assertEq(pool.balanceOf(address(guardian)), 0, "unlocked after re-request");
  }

  function test_approveWithdrawal_by_manager_allows_early_unlock() public {
    _lockAndRequest(investor, pool, investorTokens);

    uint64 validUntil = uint64(block.timestamp + WITHDRAWAL_DELAY);
    vm.expectEmit(true, true, false, true, address(guardian));
    emit WithdrawalApproved(address(pool), investor, manager, validUntil);
    vm.prank(manager);
    guardian.approveWithdrawal(address(pool), investor);

    IWithdrawalGuardian.DepositorView memory v = guardian.getDepositorView(address(pool), investor);
    assertEq(uint256(v.phase), uint256(IWithdrawalGuardian.WithdrawalPhase.Unlockable), "early unlockable");
    assertTrue(v.earlyApproved, "early approved flag");
    assertEq(v.earlyApprovalExpiry, validUntil, "approval expiry");

    // Unlock immediately, before the delay elapses.
    vm.prank(investor);
    guardian.unlock(address(pool), investorTokens);
    assertEq(pool.balanceOf(address(guardian)), 0, "early unlocked");
  }

  function test_approveWithdrawal_by_owner_allows_early_unlock() public {
    _lockAndRequest(investor, pool, investorTokens);

    vm.prank(owner);
    guardian.approveWithdrawal(address(pool), investor);

    vm.prank(investor);
    guardian.unlock(address(pool), investorTokens);
    assertEq(pool.balanceOf(address(guardian)), 0, "owner-approved early unlock");
  }

  function test_executeRecovery_sends_to_manager_approved_safe() public {
    _lockAndRequest(investor, pool, investorTokens);

    uint64 validUntil = uint64(block.timestamp + WITHDRAWAL_DELAY);
    vm.expectEmit(true, true, false, true, address(guardian));
    emit RecoveryTransferApproved(address(pool), investor, safe, manager, validUntil);
    vm.prank(manager);
    guardian.approveRecoveryTransfer(address(pool), investor, safe);

    IWithdrawalGuardian.DepositorView memory v = guardian.getDepositorView(address(pool), investor);
    assertEq(v.recoveryDestination, safe, "recovery destination");
    assertEq(v.recoveryExpiry, validUntil, "recovery expiry");

    // Warp past the depositor's pool exit cooldown; the recovery approval is still valid.
    vm.warp(block.timestamp + 1 days + 1);

    vm.expectEmit(true, true, false, true, address(guardian));
    emit RecoveryExecuted(address(pool), investor, safe, investorTokens);
    vm.prank(investor);
    guardian.executeRecovery(address(pool));

    // Funds go ONLY to the pre-approved safe, never to the caller (anti-phishing guarantee).
    assertEq(pool.balanceOf(safe), investorTokens, "funds rescued to safe");
    assertEq(pool.balanceOf(address(guardian)), 0, "guardian emptied");

    IWithdrawalGuardian.DepositorView memory cleared = guardian.getDepositorView(address(pool), investor);
    assertEq(uint256(cleared.phase), uint256(IWithdrawalGuardian.WithdrawalPhase.None), "state cleared");
    assertEq(cleared.lockedBalance, 0, "no balance");

    (address[] memory pools, ) = guardian.getDepositorPositions(investor);
    assertEq(pools.length, 0, "position removed");
  }

  function test_executeRecovery_with_owner_approval() public {
    _lockAndRequest(investor, pool, investorTokens);

    vm.prank(owner);
    guardian.approveRecoveryTransfer(address(pool), investor, safe);

    // Warp past the depositor's pool exit cooldown; the recovery approval is still valid.
    vm.warp(block.timestamp + 1 days + 1);

    vm.prank(investor);
    guardian.executeRecovery(address(pool));
    assertEq(pool.balanceOf(safe), investorTokens, "owner-approved recovery to safe");
  }

  function test_requestWithdrawal_preserves_recovery_approval() public {
    _lockAndRequest(investor, pool, investorTokens);
    vm.prank(manager);
    guardian.approveRecoveryTransfer(address(pool), investor, safe);

    // A fresh request must NOT wipe a manager-approved recovery
    _request(investor, pool);

    IWithdrawalGuardian.DepositorView memory v = guardian.getDepositorView(address(pool), investor);
    assertEq(v.recoveryDestination, safe, "recovery approval preserved across re-request");

    // Recovery remains executable to the pre-approved safe destination.
    vm.warp(block.timestamp + 1 days + 1); // clear the depositor's pool exit cooldown
    vm.prank(investor);
    guardian.executeRecovery(address(pool));
    assertEq(pool.balanceOf(safe), investorTokens, "recovery to safe still succeeds after re-request");
  }

  function test_setWithdrawalDelay_updates_window_and_emits() public {
    uint256 newDelay = 6 days;

    vm.expectEmit(false, false, false, true, address(guardian));
    emit WithdrawalDelaySet(newDelay);
    vm.prank(owner);
    guardian.setWithdrawalDelay(newDelay);

    assertEq(guardian.withdrawalDelay(), newDelay, "delay updated");

    uint256 reqTime = _lockAndRequest(investor, pool, investorTokens);
    IWithdrawalGuardian.DepositorView memory v = guardian.getDepositorView(address(pool), investor);
    assertEq(v.unlockWindowStart, reqTime + newDelay, "window start uses new delay");
    assertEq(v.unlockWindowEnd, reqTime + 2 * newDelay, "window end uses new delay");
  }

  function test_getDepositorPositions_tracks_multiple_pools() public {
    PoolLogic pool2 = _createUsdcPool("Second Vault", "SV2");
    uint256 tokens2 = _makeDeposit(pool2, investor, usdcData.asset, DEPOSIT_AMOUNT);

    _lock(investor, pool, investorTokens);
    _lock(investor, pool2, tokens2);

    (address[] memory pools, IWithdrawalGuardian.DepositorView[] memory views) = guardian.getDepositorPositions(
      investor
    );
    assertEq(pools.length, 2, "two positions");
    assertTrue(_contains(pools, address(pool)), "pool tracked");
    assertTrue(_contains(pools, address(pool2)), "pool2 tracked");
    for (uint256 i; i < views.length; ++i) {
      assertGt(views[i].lockedBalance, 0, "non-zero locked balance");
    }

    // Fully unlock one position; it drops out of the dashboard.
    uint256 reqTime = _request(investor, pool);
    vm.warp(reqTime + WITHDRAWAL_DELAY);
    vm.prank(investor);
    guardian.unlock(address(pool), investorTokens);

    (address[] memory poolsAfter, ) = guardian.getDepositorPositions(investor);
    assertEq(poolsAfter.length, 1, "one position left");
    assertEq(poolsAfter[0], address(pool2), "remaining is pool2");
  }

  function test_getPendingApprovals_lists_multiple_depositors() public {
    uint256 tokensB = _makeDeposit(pool, depositorB, usdcData.asset, DEPOSIT_AMOUNT);

    uint256 reqTime = _lockAndRequest(investor, pool, investorTokens);
    _lockAndRequest(depositorB, pool, tokensB);

    (address[] memory depositors, IWithdrawalGuardian.DepositorView[] memory views) = guardian.getPendingApprovals(
      address(pool)
    );
    assertEq(depositors.length, 2, "two pending requests");
    assertTrue(_contains(depositors, investor), "investor pending");
    assertTrue(_contains(depositors, depositorB), "depositorB pending");
    for (uint256 i; i < views.length; ++i) {
      assertEq(uint256(views[i].phase), uint256(IWithdrawalGuardian.WithdrawalPhase.Pending), "all pending");
    }

    // One depositor unlocks and drops out of the manager's pending list.
    vm.warp(reqTime + WITHDRAWAL_DELAY);
    vm.prank(investor);
    guardian.unlock(address(pool), investorTokens);

    (address[] memory depositorsAfter, ) = guardian.getPendingApprovals(address(pool));
    assertEq(depositorsAfter.length, 1, "one pending left");
    assertEq(depositorsAfter[0], depositorB, "remaining is depositorB");
  }
}
