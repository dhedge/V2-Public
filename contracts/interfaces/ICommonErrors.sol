// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

/// @title ICommonErrors
/// @notice Common error definitions shared across contracts
interface ICommonErrors {
  /// @notice Thrown when the provided address is not a valid pool
  error InvalidPool(address pool);

  /// @notice Thrown when a required address parameter is zero
  error ZeroAddress(string varName);

  /// @notice Thrown when the caller is not authorized for the operation
  error UnauthorizedCaller(address caller);
}
