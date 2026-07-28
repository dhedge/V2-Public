// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;
pragma experimental ABIEncoderV2;

import {DytmSplitTokenIdTracker} from "../../guards/assetGuards/dytm/DytmSplitTokenIdTracker.sol";
import {DytmWithdrawLib} from "../../swappers/easySwapperV2/libraries/dytm/DytmWithdrawLib.sol";

/// @title IDytmWithdrawProcessor
/// @notice External surface for the DYTM unwind processor. Sits between `WithdrawalVault`
///         (which transfers freshly-split DYTM accounts to it) and the DYTM Office
///         (which it calls back into via `delegationCall`).
interface IDytmWithdrawProcessor {
  /// @notice Full payload for one unwind. `dytmOffice`, `pool` and `splitPositions` are supplied
  ///         by the calling lib (runtime context); `actions` and `outputAsset` come from the
  ///         user-supplied `DytmWithdrawLib.UnwindPlan` in `ComplexAsset.withdrawData`.
  /// @dev    `pool` is where the processor returns any sub-$1 GM dust remnant a split account
  ///         can't be fully drained of (Ondo rejects sub-$1 attestation swaps).
  struct UnwindPlanRequest {
    address dytmOffice;
    address pool;
    DytmSplitTokenIdTracker.SplitPosition[] splitPositions;
    DytmWithdrawLib.Action[] actions;
    address outputAsset;
  }

  /// @notice Execute the user's DYTM unwind plan in the processor's isolated context.
  /// @dev    Caller must be a `WithdrawalVault` registered with `easySwapperV2`. The caller must
  ///         have already transferred the split DYTM accounts (matching `splitPositions`) to the
  ///         processor before calling.
  /// @return received  `outputAsset` gain produced by the unwind, transferred back to the caller.
  function process(UnwindPlanRequest calldata params) external returns (uint256 received);

  /// @notice Canonical settlement token enforced by `DytmWithdrawLib` as `plan.outputAsset`.
  function usdc() external view returns (address);
}
