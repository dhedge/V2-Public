// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;

library OdosLimitOrderTypeHashLib {
  /// @notice Permit2 token permissions structure
  /// @param token The token address being permitted
  /// @param amount The amount of tokens permitted
  struct TokenPermissions {
    address token;
    uint256 amount;
  }

  /// @notice Odos limit order token info structure
  /// @param tokenAddress The address of the token
  /// @param tokenAmount The amount of tokens
  struct TokenInfo {
    address tokenAddress;
    uint256 tokenAmount;
  }

  /// @notice Odos limit order structure (the "witness" in Permit2 terms)
  /// @param input The token being sold
  /// @param output The token being bought
  /// @param expiry Order expiration timestamp
  /// @param salt Unique salt for order uniqueness
  /// @param referralCode Odos referral code
  /// @param referralFee Fee percentage for referral
  /// @param referralFeeRecipient Address to receive referral fees
  /// @param partiallyFillable Whether the order can be partially filled
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

  /// @notice Permit2 PermitWitnessTransferFrom message structure
  /// @param permitted The token and amount being permitted for transfer
  /// @param spender The address allowed to spend (Odos router)
  /// @param nonce Unique nonce for replay protection
  /// @param deadline Permit expiration timestamp
  /// @param witness The Odos limit order details
  struct PermitWitnessTransferFrom {
    TokenPermissions permitted;
    address spender;
    uint256 nonce;
    uint256 deadline;
    LimitOrder witness;
  }

  /// @notice EIP-712 domain structure
  /// @param name Domain name (should be "Permit2")
  /// @param chainId The chain ID
  /// @param verifyingContract The Permit2 contract address
  struct EIP712Domain {
    string name;
    uint256 chainId;
    address verifyingContract;
  }

  /// @notice Complete EIP-712 typed data structure for Odos limit orders
  /// @param domain The EIP-712 domain
  /// @param message The PermitWitnessTransferFrom message
  struct OdosLimitOrderTypedData {
    EIP712Domain domain;
    PermitWitnessTransferFrom message;
  }

  // ============ EIP-712 Type Hashes ============
  // These must match the Permit2/Odos contract type hashes exactly

  /// @dev EIP-712 typehash for TokenPermissions
  bytes32 public constant TOKEN_PERMISSIONS_TYPEHASH = keccak256("TokenPermissions(address token,uint256 amount)");

  /// @dev EIP-712 typehash for TokenInfo
  bytes32 public constant TOKEN_INFO_TYPEHASH = keccak256("TokenInfo(address tokenAddress,uint256 tokenAmount)");

  /// @dev EIP-712 typehash for LimitOrder (includes nested TokenInfo type)
  bytes32 public constant LIMIT_ORDER_TYPEHASH =
    keccak256(
      "LimitOrder("
      "TokenInfo input,"
      "TokenInfo output,"
      "uint256 expiry,"
      "uint256 salt,"
      "uint64 referralCode,"
      "uint64 referralFee,"
      "address referralFeeRecipient,"
      "bool partiallyFillable"
      ")"
      "TokenInfo(address tokenAddress,uint256 tokenAmount)"
    );

  /// @dev EIP-712 typehash for PermitWitnessTransferFrom with LimitOrder witness
  /// @notice This MUST match exactly what Permit2 computes internally.
  /// Permit2 computes: keccak256(STUB + witnessTypeString)
  /// Where STUB = "PermitWitnessTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline,"
  /// And witnessTypeString (from Odos) = "LimitOrder witness)LimitOrder(...)TokenInfo(...)TokenPermissions(...)"
  bytes32 public constant PERMIT_WITNESS_TRANSFER_FROM_TYPEHASH =
    keccak256(
      "PermitWitnessTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline,"
      "LimitOrder witness)"
      "LimitOrder(TokenInfo input,TokenInfo output,uint256 expiry,uint256 salt,uint64 referralCode,uint64 referralFee,address referralFeeRecipient,bool partiallyFillable)"
      "TokenInfo(address tokenAddress,uint256 tokenAmount)"
      "TokenPermissions(address token,uint256 amount)"
    );

  /// @dev EIP-712 domain typehash
  bytes32 public constant EIP712_DOMAIN_TYPEHASH =
    keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");
}
