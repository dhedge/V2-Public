// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;

/// @title IDataValidator
/// @notice Interface for the data validator contract that validates off-chain structured data
/// @dev Used to verify that order data has been pre-validated before allowing it to be used by external protocols
interface IDataValidator {
  /// @notice Check if a hash has been validated and approved for a specific pool
  /// @param pool The pool address to check the hash for
  /// @param hash The EIP-712 typed data hash to check
  /// @return exists True if the hash has been validated and approved for the pool, false otherwise
  function isValidatedHash(address pool, bytes32 hash) external view returns (bool exists);

  /// @notice Check if a pool has any active (non-expired) orders involving a specific token
  /// @dev Used by PoolManagerLogic to prevent removal of tokens that are part of active orders
  /// @param pool The pool address to check
  /// @param token The token address to check
  /// @return True if there's at least one active order using this token, false otherwise
  function hasActiveOrderWithToken(address pool, address token) external view returns (bool);
}
