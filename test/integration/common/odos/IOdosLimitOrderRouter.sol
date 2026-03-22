// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

/// @title IOdosLimitOrderRouter
/// @notice Interface for interacting with the Odos Limit Order Router
/// @dev Minimal interface for testing fillLimitOrderPermit2 function
interface IOdosLimitOrderRouter {
  /// @dev Token address and amount
  struct TokenInfo {
    address tokenAddress;
    uint256 tokenAmount;
  }

  /// @dev Single input and output limit order structure
  struct LimitOrder {
    TokenInfo input;
    TokenInfo output;
    uint256 expiry;
    uint256 salt;
    uint64 referralCode;
    uint64 referralFee;
    address referralFeeRecipient;
    bool partiallyFillable;
  }

  /// @dev The execution context provided by the filler for single token limit order
  struct LimitOrderContext {
    bytes pathDefinition;
    address odosExecutor;
    uint256 currentAmount;
    address inputReceiver;
    uint256 minSurplus;
    uint256 orderType;
  }

  /// @dev Contains information required for Permit2 token transfer
  struct Permit2Info {
    address contractAddress;
    uint256 nonce;
    uint256 deadline;
    address orderOwner;
    bytes signature;
  }

  /// @notice Tries to execute a single input limit order via Permit2
  /// @param order Single input limit order struct
  /// @param context Execution context
  /// @param permit2 Permit2 struct
  /// @return orderHash Order hash
  function fillLimitOrderPermit2(
    LimitOrder calldata order,
    LimitOrderContext calldata context,
    Permit2Info calldata permit2
  ) external returns (bytes32 orderHash);

  /// @notice Check if an address is allowed to fill orders
  function allowedFillers(address) external view returns (bool);

  /// @notice Add an address to the list of allowed fillers (onlyOwner)
  function addAllowedFiller(address account) external;

  function owner() external view returns (address);
}
