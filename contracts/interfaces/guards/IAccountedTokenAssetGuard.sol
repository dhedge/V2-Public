// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;

/// @notice Optional asset guard capability: declares tokens that must not be sold through generic swap guards.
/// @dev Covers both unsupported receipt tokens valued through a supported umbrella asset (e.g. Aave aTokens)
///      and supported tokens whose value is incorporated into a composite position (e.g. GMX market tokens).
///      These tokens must be unwound through their protocol-specific guarded flow so their value is measured
///      correctly.
interface IAccountedTokenAssetGuard {
  /// @notice Capability flag, probed before `isAccountedToken`.
  function isAccountedTokenAssetGuard() external view returns (bool);

  /// @param pool The pool whose position is being checked.
  /// @param asset The supported asset this guard is registered for.
  /// @param token The proposed generic swap source token.
  /// @return accounted True if `token` is accounted for by this guard and must be unwound through its protocol.
  function isAccountedToken(address pool, address asset, address token) external view returns (bool accounted);
}
