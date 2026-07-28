//
//        __  __    __  ________  _______    ______   ________
//       /  |/  |  /  |/        |/       \  /      \ /        |
//   ____$$ |$$ |  $$ |$$$$$$$$/ $$$$$$$  |/$$$$$$  |$$$$$$$$/
//  /    $$ |$$ |__$$ |$$ |__    $$ |  $$ |$$ | _$$/ $$ |__
// /$$$$$$$ |$$    $$ |$$    |   $$ |  $$ |$$ |/    |$$    |
// $$ |  $$ |$$$$$$$$ |$$$$$/    $$ |  $$ |$$ |$$$$ |$$$$$/
// $$ \__$$ |$$ |  $$ |$$ |_____ $$ |__$$ |$$ \__$$ |$$ |_____
// $$    $$ |$$ |  $$ |$$       |$$    $$/ $$    $$/ $$       |
//  $$$$$$$/ $$/   $$/ $$$$$$$$/ $$$$$$$/   $$$$$$/  $$$$$$$$/
//
// dHEDGE DAO - https://dhedge.org
//
// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Initializable} from "@openzeppelin/v5/contracts-upgradeable/proxy/utils/Initializable.sol";
import {EnumerableSet} from "@openzeppelin/v5/contracts/utils/structs/EnumerableSet.sol";
import {SafeERC20} from "@openzeppelin/v5/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/v5/contracts/token/ERC20/IERC20.sol";

import {ICommonErrors} from "../interfaces/ICommonErrors.sol";
import {IHasOwnable} from "../interfaces/IHasOwnable.sol";
import {IManaged} from "../interfaces/IManaged.sol";
import {IPoolFactory} from "../interfaces/IPoolFactory.sol";
import {IPoolLogic} from "../interfaces/IPoolLogic.sol";

/// @title WithdrawalGuardian
/// @notice Opt-in, depositor-controlled time-lock for dHEDGE pool tokens that guards against phishing.
/// @dev Depositors `lock` pool tokens into the guardian's custody. Reclaiming them requires a
///      `requestWithdrawal` followed by a global delay, and is only possible within the bounded window
///      `[request + delay, request + 2*delay)`.
///
///      The pool manager or protocol owner may early-approve a pending request (`approveWithdrawal`) or
///      whitelist a single safe destination (`approveRecoveryTransfer`); only the depositor executes the
///      recovery (`executeRecovery`), so no other party can choose where funds go. Tokens only ever leave
///      back to the depositor (`unlock`) or to that pre-approved safe address (`executeRecovery`).
contract WithdrawalGuardian is Initializable, ICommonErrors {
  using SafeERC20 for IERC20;
  using EnumerableSet for EnumerableSet.AddressSet;

  ////////////////////////////////
  //      Structs & Enums       //
  ////////////////////////////////

  /// @dev Per (pool, depositor) protection state. Field order is append-only for upgrade safety.
  struct DepositorState {
    uint256 lockedBalance; // slot 0: pool tokens custodied for the depositor
    uint64 requestTime; // slot 1: timestamp of the pending withdrawal request (0 = none)
    uint64 approvalExpiry; // slot 1: manager/owner early-unlock expiry (0 = none)
    address recoveryDestination; // slot 2: manager/owner-approved safe destination (address(0) = none)
    uint64 recoveryExpiry; // slot 2: recovery-destination approval expiry (0 = none)
  }

  /// @notice Lifecycle phase of a depositor's custodied balance in a pool, for UI rendering.
  enum WithdrawalPhase {
    None, // nothing custodied
    Idle, // custodied, no pending withdrawal request
    Pending, // request open, delay still counting down
    Unlockable, // within the unlock window, or covered by a manager/owner early approval
    Expired // request matured but the unlock window lapsed unused; must request again
  }

  /// @notice Aggregate, UI-facing snapshot of a depositor's protection state for a given pool.
  struct DepositorView {
    WithdrawalPhase phase; // current lifecycle phase
    uint256 lockedBalance; // pool tokens custodied for the depositor
    uint256 requestTime; // pending withdrawal request timestamp (0 = none)
    uint256 unlockWindowStart; // requestTime + delay (0 if no request)
    uint256 unlockWindowEnd; // requestTime + 2*delay (0 if no request)
    uint256 secondsUntilUnlock; // seconds until the window opens (0 if open / none)
    uint256 secondsUntilExpiry; // seconds left to act while unlockable (0 otherwise)
    bool earlyApproved; // a valid (non-expired) manager/owner early approval exists
    uint256 earlyApprovalExpiry; // early-approval expiry (0 = none)
    address recoveryDestination; // valid recovery destination (address(0) if none/expired)
    uint256 recoveryExpiry; // recovery-destination approval expiry (0 = none)
    uint256 withdrawalDelay; // delay snapshot, so the UI renders from a single call
  }

  ////////////////////////////////
  //         Constants          //
  ////////////////////////////////

  /// @notice Lower bound for the global withdrawal delay (prevents a meaningless / zero delay).
  uint256 private constant MIN_WITHDRAWAL_DELAY = 24 hours;

  /// @notice Upper bound for the global withdrawal delay (prevents trapping funds for an absurd period).
  uint256 private constant MAX_WITHDRAWAL_DELAY = 30 days;

  ////////////////////////////////
  //          Storage           //
  ////////////////////////////////

  /// @notice Global delay (in seconds) enforced between a withdrawal request and its maturity.
  uint256 public withdrawalDelay;

  /// @notice The dHEDGE pool factory, used as the trusted source of truth for validating pools.
  /// @dev Set once during initialization; intentionally has no setter. If one ever becomes necessary
  ///      (unlikely), it can be added in a future upgrade.
  IPoolFactory public poolFactory;

  /// @dev pool => depositor => protection state.
  mapping(address pool => mapping(address depositor => DepositorState state)) internal _depositorState;

  /// @dev depositor => set of pools they currently have a non-zero custodied balance in. Kept in sync
  ///      with `lockedBalance`: a pool is present iff the depositor's `lockedBalance` in it is > 0.
  mapping(address depositor => EnumerableSet.AddressSet pools) internal _depositorPools;

  /// @dev pool => set of depositors with an open withdrawal request (any phase). A depositor is present
  ///      from `requestWithdrawal` until the request is consumed by `unlock` / `executeRecovery`.
  mapping(address pool => EnumerableSet.AddressSet depositors) internal _poolPendingRequests;

  ////////////////////////////////
  //           Events           //
  ////////////////////////////////

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

  ////////////////////////////////
  //           Errors           //
  ////////////////////////////////

  error ZeroAmount();

  error NothingLocked();

  error InsufficientLockedBalance();

  error WithdrawalLocked();

  error NoPendingRequest();

  error NoRecoveryApproved();

  error InvalidDelay(uint256 delay);

  ////////////////////////////////
  //          Modifiers         //
  ////////////////////////////////

  /// @dev Restricts to the protocol (factory) owner. The guardian holds no owner state of its own; it
  ///      defers to the trusted pool factory's owner so a single multisig governs both.
  modifier onlyOwner() {
    _requireOwner();
    _;
  }

  /// @dev Restricts to legitimate dHEDGE vaults registered with the trusted pool factory.
  modifier onlyValidPool(address pool) {
    _validatePool(pool);
    _;
  }

  /// @dev Restricts to the pool's manager or the protocol (factory) owner.
  modifier onlyManagerOrOwner(address pool) {
    _requireManagerOrOwner(pool);
    _;
  }

  ////////////////////////////////
  //          Functions         //
  ////////////////////////////////

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /// @notice Initialize the guardian.
  /// @dev The guardian has no owner of its own; the protocol (factory) owner governs `onlyOwner` actions.
  /// @param poolFactory_ The dHEDGE pool factory used to validate pools and resolve the protocol owner
  /// @param withdrawalDelay_ The initial global withdrawal delay in seconds
  function initialize(IPoolFactory poolFactory_, uint256 withdrawalDelay_) external initializer {
    if (address(poolFactory_) == address(0)) revert ZeroAddress("poolFactory");

    poolFactory = poolFactory_;

    _setWithdrawalDelay(withdrawalDelay_);
  }

  /// @notice Set the global withdrawal delay (in seconds).
  /// @param newDelay_ The new withdrawal delay, bounded by [MIN_WITHDRAWAL_DELAY, MAX_WITHDRAWAL_DELAY]
  function setWithdrawalDelay(uint256 newDelay_) external onlyOwner {
    _setWithdrawalDelay(newDelay_);
  }

  /// @notice Opt in by moving pool tokens into the guardian's custody.
  /// @dev The caller must have approved this contract for `amount` of `pool` tokens. The guardian must
  ///      be on the factory's `receiverWhitelist` for the transfer to bypass the depositor's exit cooldown.
  /// @param pool The dHEDGE vault (pool token) to lock
  /// @param amount The amount of pool tokens to lock
  function lock(address pool, uint256 amount) external onlyValidPool(pool) {
    if (amount == 0) revert ZeroAmount();

    _depositorState[pool][msg.sender].lockedBalance += amount;
    _depositorPools[msg.sender].add(pool); // idempotent; no-op if already tracked

    IERC20(pool).safeTransferFrom(msg.sender, address(this), amount);

    emit Locked(pool, msg.sender, amount);
  }

  /// @notice Start the withdrawal delay countdown for the caller's custodied balance in `pool`.
  /// @dev Resets any prior early approval and (re)opens the request. A manager/owner-approved recovery is
  ///      deliberately preserved. The recovery approval still lapses on its own `recoveryExpiry` or when
  ///      the manager replaces it.
  /// @param pool The dHEDGE vault the request applies to
  function requestWithdrawal(address pool) external onlyValidPool(pool) {
    DepositorState storage state = _depositorState[pool][msg.sender];
    if (state.lockedBalance == 0) revert NothingLocked();

    // Reset the request and any early-unlock approval, but keep any manager-approved recovery intact.
    state.requestTime = uint64(block.timestamp);
    state.approvalExpiry = 0;
    _poolPendingRequests[pool].add(msg.sender); // idempotent

    emit WithdrawalRequested(pool, msg.sender, _validUntil());
  }

  /// @notice Reclaim custodied pool tokens to the caller once unlocked.
  /// @dev Requires a matured request (within its bounded window) or a valid manager/owner early approval.
  ///      Resets the whole cycle (request, early approval, and any recovery approval), re-locking any
  ///      remaining balance until a fresh request matures.
  /// @param pool The dHEDGE vault to unlock from
  /// @param amount The amount of pool tokens to return to the caller
  function unlock(address pool, uint256 amount) external onlyValidPool(pool) {
    DepositorState storage state = _depositorState[pool][msg.sender];
    if (amount == 0) revert ZeroAmount();
    if (state.lockedBalance < amount) revert InsufficientLockedBalance();
    if (!_isUnlocked(state)) revert WithdrawalLocked();

    state.lockedBalance -= amount;
    _resetCycle(state);
    _poolPendingRequests[pool].remove(msg.sender); // request consumed
    if (state.lockedBalance == 0) {
      _depositorPools[msg.sender].remove(pool);
    }

    IERC20(pool).safeTransfer(msg.sender, amount);

    emit Unlocked(pool, msg.sender, amount);
  }

  /// @notice Early-approve a depositor's pending withdrawal, bypassing the delay for one delay window.
  /// @dev Callable by the pool manager or the protocol (factory) owner. Requires a request that is still
  ///      live (not yet rolled into the `Expired` phase), so a manager can only fast-track a withdrawal the
  ///      depositor requested recently — never revive a long-forgotten, stale request.
  ///      Unlike `approveRecoveryTransfer`, this returns funds to the depositor's own (possibly compromised)
  ///      wallet, so only use it for a request confirmed legitimate with the depositor; use recovery if phished.
  /// @param pool The dHEDGE vault the depositor locked into
  /// @param depositor The depositor whose withdrawal is approved
  function approveWithdrawal(address pool, address depositor) external onlyValidPool(pool) onlyManagerOrOwner(pool) {
    DepositorState storage state = _depositorState[pool][depositor];
    // Reject a request that has no open cycle or has already expired (rolled past its unlock window).
    if (state.requestTime == 0 || block.timestamp >= state.requestTime + withdrawalDelay * 2) {
      revert NoPendingRequest();
    }

    uint64 validUntil = _validUntil();
    state.approvalExpiry = validUntil;

    emit WithdrawalApproved(pool, depositor, msg.sender, validUntil);
  }

  /// @notice Whitelist a single safe destination a (potentially compromised) depositor may recover to.
  /// @dev Callable by the pool manager or the protocol (factory) owner in response to a pending request.
  ///      This never moves tokens itself; only the depositor can execute the recovery, and only to this
  ///      pre-approved destination. The approval lapses at `block.timestamp + withdrawalDelay`.
  /// @param pool The dHEDGE vault the depositor locked into
  /// @param depositor The depositor whose tokens may be rescued
  /// @param safeAddress The single safe destination the depositor is allowed to recover to
  function approveRecoveryTransfer(
    address pool,
    address depositor,
    address safeAddress
  ) external onlyValidPool(pool) onlyManagerOrOwner(pool) {
    if (safeAddress == address(0)) revert ZeroAddress("safeAddress");

    DepositorState storage state = _depositorState[pool][depositor];
    if (state.requestTime == 0) revert NoPendingRequest();

    uint64 validUntil = _validUntil();
    state.recoveryDestination = safeAddress;
    state.recoveryExpiry = validUntil;

    emit RecoveryTransferApproved(pool, depositor, safeAddress, msg.sender, validUntil);
  }

  /// @notice Move the caller's entire custodied balance to the manager/owner-approved safe destination.
  /// @dev Executed by the depositor (`msg.sender`) so no other party can choose where funds go. Immediate
  ///      (bypasses the guardian delay) because the destination is constrained to the pre-approved safe
  ///      address. Still blocked while the caller is within their pool exit cooldown, so recovery to a fresh
  ///      (zero-cooldown) address cannot be used to escape that cooldown.
  /// @param pool The dHEDGE vault to recover from
  function executeRecovery(address pool) external onlyValidPool(pool) {
    DepositorState storage state = _depositorState[pool][msg.sender];

    address destination = state.recoveryDestination;
    if (destination == address(0) || block.timestamp >= state.recoveryExpiry) revert NoRecoveryApproved();

    // The safe destination is a fresh address with no exit cooldown of its own. Don't let recovery route
    // tokens there while the caller is still within their pool exit cooldown, which would bypass it.
    if (IPoolLogic(pool).getExitRemainingCooldown(msg.sender) > 0) revert WithdrawalLocked();

    uint256 amount = state.lockedBalance;
    if (amount == 0) revert NothingLocked();

    state.lockedBalance = 0;
    _resetCycle(state);
    _poolPendingRequests[pool].remove(msg.sender);
    _depositorPools[msg.sender].remove(pool);

    IERC20(pool).safeTransfer(destination, amount);

    emit RecoveryExecuted(pool, msg.sender, destination, amount);
  }

  /// @notice Full UI snapshot of a depositor's protection state for `pool`.
  function getDepositorView(address pool, address depositor) external view returns (DepositorView memory) {
    return _depositorView(pool, depositor);
  }

  /// @notice One-call dashboard of every pool `depositor` currently has a custodied balance in.
  /// @dev For off-chain reads; the returned arrays are unbounded by the depositor's distinct pool count.
  function getDepositorPositions(
    address depositor
  ) external view returns (address[] memory pools, DepositorView[] memory views) {
    pools = _depositorPools[depositor].values();
    views = new DepositorView[](pools.length);
    for (uint256 i; i < pools.length; ++i) {
      views[i] = _depositorView(pools[i], depositor);
    }
  }

  /// @notice Full snapshot of every depositor with an open request in `pool`, for the manager dashboard.
  function getPendingApprovals(
    address pool
  ) external view returns (address[] memory depositors, DepositorView[] memory views) {
    depositors = _poolPendingRequests[pool].values();
    views = new DepositorView[](depositors.length);
    for (uint256 i; i < depositors.length; ++i) {
      views[i] = _depositorView(pool, depositors[i]);
    }
  }

  function _setWithdrawalDelay(uint256 newDelay_) internal {
    if (newDelay_ < MIN_WITHDRAWAL_DELAY || newDelay_ > MAX_WITHDRAWAL_DELAY) revert InvalidDelay(newDelay_);

    withdrawalDelay = newDelay_;

    emit WithdrawalDelaySet(newDelay_);
  }

  /// @dev Ends the current withdrawal cycle, clearing every per-cycle approval (pending request,
  ///      early-unlock approval, and recovery approval) so the next cycle starts from a clean slate.
  ///      Leaves `lockedBalance` untouched; the caller adjusts it before calling.
  function _resetCycle(DepositorState storage state) internal {
    state.requestTime = 0;
    state.approvalExpiry = 0;
    state.recoveryDestination = address(0);
    state.recoveryExpiry = 0;
  }

  /// @dev Unlocked while a manager/owner early approval is valid, or within the bounded request window
  ///      `[requestTime + delay, requestTime + 2*delay)`. The bounded window re-locks a matured-but-unused
  ///      request (anti-staleness). `delay == 0` is treated as an immediate unlock so funds can never be
  ///      permanently trapped (defensive; the setter enforces `delay >= MIN_WITHDRAWAL_DELAY`).
  function _isUnlocked(DepositorState storage state) internal view returns (bool unlocked) {
    if (block.timestamp < state.approvalExpiry) {
      return true;
    }

    uint256 requestTime = state.requestTime;
    if (requestTime == 0) {
      return false;
    }

    uint256 delay = withdrawalDelay;
    if (delay == 0) {
      return true;
    }

    uint256 unlockStart = requestTime + delay;
    unlocked = block.timestamp >= unlockStart && block.timestamp < unlockStart + delay;
  }

  /// @dev Builds the UI snapshot for a (pool, depositor), deriving phase and timing from current state.
  function _depositorView(address pool, address depositor) private view returns (DepositorView memory snapshot) {
    DepositorState storage state = _depositorState[pool][depositor];
    uint256 delay = withdrawalDelay;
    uint256 requestTime = state.requestTime;

    snapshot.lockedBalance = state.lockedBalance;
    snapshot.requestTime = requestTime;
    snapshot.earlyApprovalExpiry = state.approvalExpiry;
    snapshot.earlyApproved = block.timestamp < state.approvalExpiry;
    snapshot.recoveryExpiry = state.recoveryExpiry;
    snapshot.recoveryDestination = block.timestamp < state.recoveryExpiry ? state.recoveryDestination : address(0);
    snapshot.withdrawalDelay = delay;

    if (requestTime != 0) {
      snapshot.unlockWindowStart = requestTime + delay;
      snapshot.unlockWindowEnd = requestTime + delay * 2;
    }

    WithdrawalPhase phase = _phase(state);
    snapshot.phase = phase;

    if (phase == WithdrawalPhase.Pending) {
      snapshot.secondsUntilUnlock = snapshot.unlockWindowStart - block.timestamp;
    } else if (phase == WithdrawalPhase.Unlockable) {
      uint256 deadline = snapshot.earlyApproved ? state.approvalExpiry : snapshot.unlockWindowEnd;
      if (deadline > block.timestamp) {
        snapshot.secondsUntilExpiry = deadline - block.timestamp;
      }
    }
  }

  /// @dev Lifecycle phase, consistent with `_isUnlocked` (Unlockable iff a real unlock would succeed).
  function _phase(DepositorState storage state) private view returns (WithdrawalPhase) {
    if (state.lockedBalance == 0) {
      return WithdrawalPhase.None;
    }
    if (state.requestTime == 0) {
      return WithdrawalPhase.Idle;
    }
    if (_isUnlocked(state)) {
      return WithdrawalPhase.Unlockable;
    }
    // Open request that isn't unlockable: before the window => Pending, after it => Expired.
    return block.timestamp < state.requestTime + withdrawalDelay ? WithdrawalPhase.Pending : WithdrawalPhase.Expired;
  }

  /// @dev Resolves the manager from the (already validated) pool and the protocol owner from the trusted
  ///      factory — never from an address supplied/derived by an untrusted pool.
  function _requireManagerOrOwner(address pool) private view {
    address manager = IManaged(IPoolLogic(pool).poolManagerLogic()).manager();

    if (msg.sender != manager && msg.sender != _protocolOwner()) revert UnauthorizedCaller(msg.sender);
  }

  /// @dev Reverts unless the caller is the protocol (factory) owner.
  function _requireOwner() private view {
    if (msg.sender != _protocolOwner()) revert UnauthorizedCaller(msg.sender);
  }

  /// @dev The protocol owner, read from the trusted pool factory (the guardian holds no owner state).
  function _protocolOwner() private view returns (address protocolOwner) {
    protocolOwner = IHasOwnable(address(poolFactory)).owner();
  }

  /// @dev Reverts unless `pool` is a vault registered with the trusted pool factory.
  function _validatePool(address pool) private view {
    if (!poolFactory.isPool(pool)) revert InvalidPool(pool);
  }

  /// @dev Approval/maturity deadline measured from now, shared by the request and approval flows.
  function _validUntil() private view returns (uint64 validUntil) {
    validUntil = uint64(block.timestamp + withdrawalDelay);
  }
}
