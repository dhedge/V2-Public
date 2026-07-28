// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;
pragma experimental ABIEncoderV2;

/// @notice Interface exposing the async-redemption request tracking maintained by the
///         Midas redemption vault contract guard, consumed by the pending-redemption asset guard.
interface IMidasRedemptionVaultContractGuard {
  /// @notice Returns the redemption request ids opened by `pool` on `vault` that the guard has recorded.
  /// @dev The list is pruned of Processed requests as new requests are opened, but may still contain
  ///      non-Pending ids between requests; consumers must confirm status against the vault before
  ///      relying on an id being Pending. Canceled ids stay until `reconcileCanceledRequests`.
  function getPendingRequestIds(address pool, address vault) external view returns (uint256[] memory requestIds);

  /// @notice Permissionless cleanup: removes recorded ids whose request is Processed.
  function pruneSettledRequests(address pool, address vault) external;

  /// @notice Guard-owner-only cleanup of Canceled ids, lifting the pricing freeze after Midas ops
  ///         returned the rejected mTokens to the pool.
  function reconcileCanceledRequests(address pool, address vault) external;
}
