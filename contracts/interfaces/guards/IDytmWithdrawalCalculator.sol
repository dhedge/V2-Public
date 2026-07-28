// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;
pragma experimental ABIEncoderV2;

import {IComplexAssetGuard} from "./IComplexAssetGuard.sol";
import {DytmParamStructs} from "../../utils/dytm/DytmParamStructs.sol";

/// @title IDytmWithdrawalCalculator
/// @notice Calculator-side surface for DYTM-as-collateral withdrawals. Exposes a single
///         simulation-only entrypoint (`previewWithdrawal`) that emits a flat per-asset
///         view of the withdrawal — one `AssetData` entry per collateral and per debt slot
///         across all withdrawable markets. The frontend uses this to plan both off-chain work
///         (DEX swaps, Pendle redeems, Ondo attestations) and on-chain `WithdrawParams` /
///         `RepayParams` calldata in a single round-trip.
/// @dev    The runtime withdrawal payload is `DytmWithdrawLib.UnwindPlan` — a flat list of
///         `(target, calldata)` actions plus an output-asset slippage floor. The library runs in
///         the WithdrawalVault and executes the action sequence as the owner of the freshly-split
///         DYTM accounts; the frontend builds the actions and minOutputAmount offchain.
interface IDytmWithdrawalCalculator is IComplexAssetGuard {
  /// @notice Emit the per-asset planning view for a withdrawal of `poolTokenAmount` from `pool`.
  /// @dev    State-mutating in practice (mints manager fee + accrues DYTM market interest);
  ///         intended to be called via `callStatic` / `eth_call` so neither commits.
  /// @param  pool            Pool logic address.
  /// @param  poolTokenAmount Pool tokens the user intends to withdraw.
  /// @return assetData       Flat list of withdrawal-planning entries across all withdrawable markets.
  function previewWithdrawal(
    address pool,
    uint256 poolTokenAmount
  ) external returns (DytmParamStructs.AssetData[] memory assetData);
}
