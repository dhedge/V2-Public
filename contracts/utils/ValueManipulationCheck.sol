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

pragma solidity 0.8.28;

import {IValueManipulationCheck} from "../interfaces/IValueManipulationCheck.sol";

/// @title ValueManipulationCheck
/// @notice Prevents atomic vault value manipulation by tracking fund value changes within a transaction
/// @dev Uses transient storage (EIP-1153) to track expected fund value within a transaction.
///      This prevents flashloan-based attacks where an attacker could manipulate fund value via donations.
///
///      Implementation approach:
///      - On first vault action, store the current fundValue + expected change as the expected next value
///      - On subsequent vault actions, verify current fundValue matches expected, then update expected
///      - If fundValue doesn't match expected, revert to prevent atomic value manipulation
///
///      This approach is simpler than tracking token price because:
///      - Fund value changes are predictable: deposits add value, withdrawals remove value
///      - Fee configurations (poolFeeShare, entry/exit fees) don't affect fund value tracking
///      - Manipulation (donations) will cause unexpected fund value changes
///
///      Transient storage is used because:
///      - It's automatically cleared at the end of the transaction
///      - It's cheaper than SSTORE/SLOAD for single-transaction state
///      - It perfectly fits the use case of preventing intra-transaction manipulation
contract ValueManipulationCheck is IValueManipulationCheck {
  /// @notice Maximum allowed absolute value difference to account for rounding errors
  /// @dev Set to 1e15 (0.001 in 18 decimal terms, or about $0.001 for USD-based pools)
  ///      This allows for minor rounding errors while catching meaningful manipulation
  uint256 public constant MAX_VALUE_TOLERANCE = 1e15;

  /// @notice Error thrown when unexpected fund value change is detected within a transaction
  /// @param pool The pool address where value manipulation was detected
  /// @param expectedValue The expected fund value based on previous operations
  /// @param actualValue The actual current fund value
  error ValueManipulationDetected(address pool, uint256 expectedValue, uint256 actualValue);

  /// @notice Error thrown when different operation types are mixed in a single transaction
  /// @param pool The pool address where operation type mismatch was detected
  /// @param firstOperation The operation type of the first action in the transaction
  /// @param attemptedOperation The operation type that was attempted
  error OperationTypeMismatch(address pool, OperationType firstOperation, OperationType attemptedOperation);

  /// @notice Error thrown when caller is not the pool
  /// @param caller The address that attempted to call the function
  /// @param pool The pool address that was passed as parameter
  error OnlyPool(address caller, address pool);

  /// @notice Checks fund value for manipulation and updates expected value
  /// @dev On first call: stores expectedFundValueAfter as the expected value for next operation
  ///      On subsequent calls: verifies currentFundValue matches stored expected value (within tolerance)
  /// @param pool The address of the pool being checked
  /// @param currentFundValue The current total fund value (before this operation's value change)
  /// @param expectedFundValueAfter The expected fund value after this operation completes
  function checkValueManipulation(address pool, uint256 currentFundValue, uint256 expectedFundValueAfter) external {
    if (msg.sender != pool) revert OnlyPool(msg.sender, pool);

    uint256 storedExpectedValue = _getStoredFundValue(pool);

    if (storedExpectedValue == 0) {
      // First vault action in this transaction - store expected value after this operation
      _setStoredFundValue(pool, expectedFundValueAfter);
    } else {
      // Subsequent vault action - verify fund value matches expected
      uint256 valueDiff;
      if (storedExpectedValue > currentFundValue) {
        valueDiff = storedExpectedValue - currentFundValue;
      } else {
        valueDiff = currentFundValue - storedExpectedValue;
      }

      // Revert if fund value differs from expected by more than tolerance
      if (valueDiff > MAX_VALUE_TOLERANCE) {
        revert ValueManipulationDetected(pool, storedExpectedValue, currentFundValue);
      }

      // Update expected value for next operation
      _setStoredFundValue(pool, expectedFundValueAfter);
    }
  }

  /// @notice Checks and enforces that the operation type hasn't changed within the transaction
  /// @dev This function should be called at the start of deposit, withdraw, and execTransaction operations
  /// @param pool The address of the pool being checked
  /// @param operationType The type of operation being performed
  function checkOperationType(address pool, OperationType operationType) external {
    if (msg.sender != pool) revert OnlyPool(msg.sender, pool);

    OperationType storedOperationType = _getStoredOperationType(pool);

    if (storedOperationType == OperationType.None) {
      // First operation in this transaction - store the operation type
      _setStoredOperationType(pool, operationType);
    } else {
      // Subsequent operation - check if operation type matches
      if (storedOperationType != operationType) {
        revert OperationTypeMismatch(pool, storedOperationType, operationType);
      }
    }
  }

  /// @notice Retrieves the stored expected fund value from transient storage
  /// @dev Uses EIP-1153 TLOAD opcode via assembly
  /// @param pool The pool address to get the stored value for
  /// @return fundValue The stored expected fund value (0 if not set)
  function _getStoredFundValue(address pool) private view returns (uint256 fundValue) {
    bytes32 slot = keccak256(abi.encodePacked("expectedFundValue", pool));
    assembly {
      fundValue := tload(slot)
    }
  }

  /// @notice Stores the expected fund value in transient storage
  /// @dev Uses EIP-1153 TSTORE opcode via assembly
  /// @param pool The pool address to store the value for
  /// @param fundValue The expected fund value to store
  function _setStoredFundValue(address pool, uint256 fundValue) private {
    bytes32 slot = keccak256(abi.encodePacked("expectedFundValue", pool));
    assembly {
      tstore(slot, fundValue)
    }
  }

  /// @notice Retrieves the stored operation type from transient storage
  /// @dev Uses EIP-1153 TLOAD opcode via assembly
  /// @param pool The pool address to get the stored operation type for
  /// @return operationType The stored operation type (None if not set)
  function _getStoredOperationType(address pool) private view returns (OperationType operationType) {
    bytes32 slot = keccak256(abi.encodePacked("operationType", pool));
    uint256 operationTypeValue;
    assembly {
      operationTypeValue := tload(slot)
    }
    operationType = OperationType(operationTypeValue);
  }

  /// @notice Stores the operation type in transient storage
  /// @dev Uses EIP-1153 TSTORE opcode via assembly
  /// @param pool The pool address to store the operation type for
  /// @param operationType The operation type to store
  function _setStoredOperationType(address pool, OperationType operationType) private {
    bytes32 slot = keccak256(abi.encodePacked("operationType", pool));
    assembly {
      tstore(slot, operationType)
    }
  }

  /// @notice Returns the stored expected fund value for a pool (for testing/debugging)
  /// @dev External view function to check the transient storage state
  /// @param pool The pool address to check
  /// @return The stored expected fund value (0 if not set)
  function getStoredFundValue(address pool) external view returns (uint256) {
    return _getStoredFundValue(pool);
  }

  /// @notice Returns the stored operation type for a pool (for testing/debugging)
  /// @dev External view function to check the transient storage state
  /// @param pool The pool address to check
  /// @return The stored operation type (None if not set)
  function getStoredOperationType(address pool) external view returns (OperationType) {
    return _getStoredOperationType(pool);
  }
}
