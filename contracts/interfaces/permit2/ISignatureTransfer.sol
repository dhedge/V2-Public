// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title ISignatureTransfer
/// @notice Interface for Permit2's SignatureTransfer functionality
/// @dev Subset of Permit2 interface needed for limit buy orders
interface ISignatureTransfer {
  /// @notice Token and amount being transferred
  struct TokenPermissions {
    address token;
    uint256 amount;
  }

  /// @notice The permit data for a single token transfer
  struct PermitTransferFrom {
    TokenPermissions permitted;
    uint256 nonce;
    uint256 deadline;
  }

  /// @notice Details for signature-based transfer
  struct SignatureTransferDetails {
    address to;
    uint256 requestedAmount;
  }

  /// @notice Transfers a token using a signed permit message
  /// @dev Includes extra data (witness) for additional validation
  /// @param permit The permit data signed over by the owner
  /// @param owner The owner of the tokens to transfer
  /// @param transferDetails Details of the transfer including recipient and amount
  /// @param witness Extra data to include when hashing the permit
  /// @param witnessTypeString The EIP-712 type string for the witness
  /// @param signature The signature to verify
  function permitWitnessTransferFrom(
    PermitTransferFrom calldata permit,
    SignatureTransferDetails calldata transferDetails,
    address owner,
    bytes32 witness,
    string calldata witnessTypeString,
    bytes calldata signature
  ) external;
}
