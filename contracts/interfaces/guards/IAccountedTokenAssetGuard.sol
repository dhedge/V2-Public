// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;

/// @notice Optional asset guard capability: declares receipt tokens the guard already values.
/// @dev For guards valuing a position via receipt tokens the pool holds (e.g. aToken balances) instead of
///      the supported asset's own balance. Such receipts are unregistered, so `isSupportedAsset` checks
///      miss them; swap guards use this to refuse selling them.
interface IAccountedTokenAssetGuard {
  /// @notice Capability flag, probed before `isAccountedToken`.
  function isAccountedTokenAssetGuard() external view returns (bool);

  /// @param asset The supported (umbrella) asset this guard is registered for.
  /// @return accounted True if `token`'s value is already counted by this guard for `pool`.
  function isAccountedToken(address pool, address asset, address token) external view returns (bool accounted);
}
