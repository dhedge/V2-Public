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
// Copyright (c) 2025 dHEDGE DAO
//
// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;

/// @title IValueManipulationCheck
/// @notice Interface for the ValueManipulationCheck contract
interface IValueManipulationCheck {
  /// @notice Types of operations that can be performed on a pool
  enum OperationType {
    None,
    Deposit,
    Withdraw,
    ExecTransaction
  }

  /// @notice Checks fund value for manipulation and updates expected value
  /// @dev Called at the start of deposit/withdraw operations.
  ///      On first call: stores expectedFundValueAfter as baseline for next operation
  ///      On subsequent calls: verifies currentFundValue matches expected from previous operation
  /// @param pool The address of the pool being checked
  /// @param currentFundValue The current total fund value
  /// @param expectedFundValueAfter The expected fund value after this operation completes
  function checkValueManipulation(address pool, uint256 currentFundValue, uint256 expectedFundValueAfter) external;

  /// @notice Checks and enforces that the operation type hasn't changed within the transaction
  /// @param pool The address of the pool being checked
  /// @param operationType The type of operation being performed
  function checkOperationType(address pool, OperationType operationType) external;

  /// @notice Gets the stored expected fund value for a pool from transient storage (for testing)
  /// @param pool The address of the pool
  /// @return The stored expected fund value (0 if not set in current transaction)
  function getStoredFundValue(address pool) external view returns (uint256);

  /// @notice Gets the stored operation type for a pool from transient storage (for testing)
  /// @param pool The address of the pool
  /// @return The stored operation type (None if not set in current transaction)
  function getStoredOperationType(address pool) external view returns (OperationType);
}
