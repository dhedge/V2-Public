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

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IHasSupportedAsset} from "../../../interfaces/IHasSupportedAsset.sol";
import {IMidasRedemptionVault} from "../../../interfaces/midas/IMidasRedemptionVault.sol";
import {IMidasRedemptionVaultContractGuard} from "../../../interfaces/midas/IMidasRedemptionVaultContractGuard.sol";
import {ITransactionTypes} from "../../../interfaces/ITransactionTypes.sol";
import {PoolsWhitelist} from "../../../utils/PoolsWhitelist.sol";
import {SlippageAccumulator, SlippageAccumulatorUser} from "../../../utils/SlippageAccumulatorUser.sol";
import {TxDataUtils} from "../../../utils/TxDataUtils.sol";

/// @title MidasRedemptionVaultContractGuard
/// @notice Contract guard for a Midas RedemptionVault. Allows a manager to either instantly redeem an
///         mToken to `tokenOut` (fee-bearing, atomic) or open an async redemption request, settled
///         later at the curator-approved rate. Custom-recipient overloads are blocked so redeemed
///         tokens and pending claims always belong to the pool.
/// @dev `redeemInstant` output is checked against the shared `SlippageAccumulator` using measured
///      pre/post balance deltas (the manager-supplied `minReceiveAmount` is not trusted).
///      `redeemRequest` carries no min amount (settled later at the curator-approved rate) and is
///      tracked per pool instead, so the pending-redemption asset guard (type 43) can value the
///      outstanding claim and service withdrawals while it is unsettled.
/// @dev A request can only be settled (`approveRequest`) or rejected (`rejectRequest`) by the Midas
///      vault admin — the request author cannot cancel it, so no cancel path exists in this guard.
///      On rejection the mToken is NOT auto-returned: the request just turns Canceled (terminal) and
///      Midas ops transfer the tokens back manually via `ManageableVault.withdrawToken`, which is
///      gated by `onlyVaultAdmin` (Midas vault admin role) and carries no on-chain link between the
///      transfer and the request. Until the return, the claim's value is not representable on-chain,
///      so the pending-redemption asset guard FREEZES the pool's pricing (totalFundValue — and thus
///      deposits, withdrawals and trading — reverts) the moment a tracked request turns Canceled:
///      a vault must never transact at an understated total value. Once the tokens are verifiably
///      back in the pool, the guard owner lifts the freeze via `reconcileCanceledRequests`. Both the
///      mToken and the request's `tokenOut` must stay enabled while a request is unresolved so the
///      incoming tokens are accounted — enforced by `ERC20Guard._checkMidasPendingRedemptions`.
/// @dev This guard is also the single owned contract of the Midas integration: it holds the pool
///      whitelist (`PoolsWhitelist`), enforced at configuration time (both Midas asset guards'
///      `addAssetCheck`) and, for consistency, in this guard's `txGuard`.
/// @dev REDEPLOYMENT RISK: `pendingRequestIds` (and the pool whitelist) live in this guard's storage.
///      Replacing this guard (`Governance.setContractGuard`) while any pool has a Pending request
///      makes the claim invisible to the new instance — its NAV contribution vanishes and withdrawals
///      proceed as if nothing were pending. Settle or reject all outstanding requests before swapping
///      this guard.
contract MidasRedemptionVaultContractGuard is
  TxDataUtils,
  ITransactionTypes,
  SlippageAccumulatorUser,
  PoolsWhitelist,
  IMidasRedemptionVaultContractGuard
{
  /// @notice Bounds the tracked request list per (pool, vault): every id in it costs an external
  ///         status check in each NAV computation, so unbounded growth would let a manager bloat
  ///         (and eventually brick) the pool's pricing loop with dust redemptions.
  uint256 public constant MAX_TRACKED_REQUESTS = 10;

  // Recorded async redemption request ids per pool per redemption vault (ids are vault-local
  // monotonic counters, so they must never be mixed across vaults). Pruned of settled ids as new
  // requests are opened; consumers must re-check status against the vault.
  mapping(address => mapping(address => uint256[])) private pendingRequestIds;

  constructor(
    address _slippageAccumulator,
    address[] memory _whitelistedPools
  ) SlippageAccumulatorUser(_slippageAccumulator) PoolsWhitelist(_whitelistedPools) {}

  /// @inheritdoc IMidasRedemptionVaultContractGuard
  function getPendingRequestIds(
    address _pool,
    address _vault
  ) external view override returns (uint256[] memory requestIds) {
    requestIds = pendingRequestIds[_pool][_vault];
  }

  /// @inheritdoc IMidasRedemptionVaultContractGuard
  /// @dev Between a settlement and the next `redeemRequest`, stale ids cost an external status check
  ///      in every NAV computation of the pool — anyone can call this to stop paying for them.
  ///      Only removes Processed ids, so it's safe to be permissionless; Canceled ids are deliberately
  ///      kept (they freeze pricing) and can only be removed via `reconcileCanceledRequests`.
  function pruneSettledRequests(address _pool, address _vault) external override {
    _pruneByStatus(_pool, _vault, IMidasRedemptionVault.RequestStatus.Processed);
  }

  /// @inheritdoc IMidasRedemptionVaultContractGuard
  /// @dev Owner (or a signer of the owning Safe) only: called after ops verify Midas returned the
  ///      rejected mTokens to the pool. Reconciling BEFORE the return would leave the vault's total
  ///      value understated — exactly the catastrophe the freeze exists to prevent — so this is
  ///      deliberately not permissionless and not manager-callable.
  function reconcileCanceledRequests(address _pool, address _vault) external override onlyOwnerOrSafeSigner(owner()) {
    _pruneByStatus(_pool, _vault, IMidasRedemptionVault.RequestStatus.Canceled);
  }

  /// @notice Validates a manager transaction routed to a Midas RedemptionVault.
  /// @param _poolManagerLogic Pool manager logic address.
  /// @param _to The RedemptionVault being called.
  /// @param _data Calldata of the transaction.
  /// @return txType Transaction type (Exchange) when allowed.
  /// @return isPublic Always false (manager-only).
  function txGuard(
    address _poolManagerLogic,
    address _to,
    bytes memory _data
  ) external override returns (uint16 txType, bool isPublic) {
    address poolLogic = _accessControl(_poolManagerLogic);

    // Consistent with the asset-adding gate: only whitelisted pools can transact with the vault.
    require(poolsWhitelist[poolLogic], "pool not whitelisted");

    bytes4 method = getMethod(_data);

    // `tokenOut` is the first argument of both allowed methods and must be accounted by the pool.
    address tokenOut = convert32toAddress(getInput(_data, 0));

    if (method == IMidasRedemptionVault.redeemInstant.selector) {
      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(tokenOut), "unsupported destination asset");

      address mToken = IMidasRedemptionVault(_to).mToken();

      // Record pre-execution balances; the inherited `afterTxGuard` measures the actual delta.
      intermediateSwapData = SlippageAccumulator.SwapData({
        srcAsset: mToken,
        dstAsset: tokenOut,
        srcAmount: _getBalance(mToken, poolLogic),
        dstAmount: _getBalance(tokenOut, poolLogic)
      });

      txType = uint16(TransactionType.Exchange);
    } else if (method == IMidasRedemptionVault.redeemRequest.selector) {
      // `tokenOut` must stay enabled until settlement pays it in. That stay-enabled protection
      // (`ERC20Guard._checkMidasPendingRedemptions`) lives in tokenOut's ASSET guard, so it assumes
      // tokenOut's asset type resolves to a guard inheriting ERC20Guard — true for plain ERC20
      // stablecoins like USDC, which is what Midas uses as payment tokens.
      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(tokenOut), "unsupported destination asset");
      // The pending claim is paid out of (and, on rejection, returned to) the pool's mToken position,
      // so the mToken must be an accounted asset for the claim's whole lifecycle.
      require(
        IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(IMidasRedemptionVault(_to).mToken()),
        "unsupported source asset"
      );
      // The vault must be enabled as a pending-redemption position asset so the outstanding claim
      // is valued and withdrawals against it are serviced until the request settles.
      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(_to), "pending redemption not supported");

      txType = uint16(TransactionType.Exchange);
    }

    return (txType, false);
  }

  /// @notice Post-transaction processing.
  /// @dev For `redeemInstant`: delegates to the inherited measured-delta slippage accumulation.
  ///      For `redeemRequest`: records the newly opened async request so the pending-redemption asset
  ///      guard can value it and service withdrawals against it. Called by `PoolLogic` after execution.
  function afterTxGuard(address _poolManagerLogic, address _to, bytes memory _data) public override {
    if (getMethod(_data) == IMidasRedemptionVault.redeemRequest.selector) {
      address poolLogic = _accessControl(_poolManagerLogic);

      // The just-created request was assigned the id preceding the incremented counter.
      uint256 assignedId = IMidasRedemptionVault(_to).currentRequestId() - 1;

      _pruneByStatus(poolLogic, _to, IMidasRedemptionVault.RequestStatus.Processed);
      require(pendingRequestIds[poolLogic][_to].length < MAX_TRACKED_REQUESTS, "too many pending requests");
      pendingRequestIds[poolLogic][_to].push(assignedId);
    } else {
      SlippageAccumulatorUser.afterTxGuard(_poolManagerLogic, _to, _data);
    }
  }

  /// @dev Removes ids whose request has the given status, bounding the stored list size. Iterates
  ///      backwards with swap-and-pop: an element swapped in from the tail was already inspected.
  function _pruneByStatus(address _pool, address _vault, IMidasRedemptionVault.RequestStatus _status) internal {
    uint256[] storage ids = pendingRequestIds[_pool][_vault];

    for (uint256 i = ids.length; i > 0; i--) {
      (, , uint8 status, , , ) = IMidasRedemptionVault(_vault).redeemRequests(ids[i - 1]);

      if (status == uint8(_status)) {
        ids[i - 1] = ids[ids.length - 1];
        ids.pop();
      }
    }
  }
}
