// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;

/// @title HyperliquidConstants
/// @notice Shared constants for Hyperliquid CoreWriter action IDs and related values.
/// @dev Used by both HyperliquidCoreWriterContractGuard and HyperliquidWithdrawalManager.
library HyperliquidConstants {
  /// @notice CoreWriter action IDs.
  /// @dev See https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/hyperevm/interacting-with-hypercore
  uint24 internal constant ACTION_LIMIT_ORDER = 1;
  uint24 internal constant ACTION_SPOT_SEND = 6;
  uint24 internal constant ACTION_USD_CLASS_TRANSFER = 7;
  uint24 internal constant ACTION_ADD_API_WALLET = 9;
  uint24 internal constant ACTION_OID_CANCEL = 10;
  uint24 internal constant ACTION_CLOID_CANCEL = 11;
  uint24 internal constant ACTION_SEND_ASSET = 13;
}
