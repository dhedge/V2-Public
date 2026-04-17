// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

/// @title EasyLimitBuyTypeHashLib
/// @notice Library for EIP-712 type hashes used in dHEDGE limit buy orders
/// @dev Follows Permit2's PermitWitnessTransferFrom pattern with custom witness data
library EasyLimitBuyTypeHashLib {
  /// @notice Permit2 token permissions structure
  /// @param token The token address being permitted
  /// @param amount The amount of tokens permitted
  struct TokenPermissions {
    address token;
    uint256 amount;
  }

  /// @notice dHEDGE limit buy order structure (the "witness" in Permit2 terms)
  /// @param owner User address that created the order
  /// @param targetVault dHEDGE vault to deposit into
  /// @param pricingAsset Asset whose price triggers order execution
  /// @param minTriggerPriceD18 Lower price bound (0 = no lower bound)
  /// @param maxTriggerPriceD18 Upper price bound (type(uint256).max = no upper bound)
  /// @param slippageToleranceBps User-defined slippage tolerance in basis points
  struct LimitBuyOrder {
    address owner;
    address targetVault;
    address pricingAsset;
    uint256 minTriggerPriceD18;
    uint256 maxTriggerPriceD18;
    uint16 slippageToleranceBps;
  }

  /// @notice Permit2 PermitWitnessTransferFrom message structure
  /// @param permitted The token and amount being permitted for transfer
  /// @param spender The address allowed to spend (LimitBuyManager)
  /// @param nonce Unique nonce for replay protection
  /// @param deadline Permit expiration timestamp
  /// @param witness The limit buy order details
  struct PermitWitnessTransferFrom {
    TokenPermissions permitted;
    address spender;
    uint256 nonce;
    uint256 deadline;
    LimitBuyOrder witness;
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

  /// @notice Complete EIP-712 typed data structure for limit buy orders
  /// @param domain The EIP-712 domain
  /// @param message The PermitWitnessTransferFrom message
  struct LimitBuyTypedData {
    EIP712Domain domain;
    PermitWitnessTransferFrom message;
  }

  // ============ EIP-712 Type Hashes ============

  /// @dev EIP-712 typehash for TokenPermissions
  bytes32 public constant TOKEN_PERMISSIONS_TYPEHASH = keccak256("TokenPermissions(address token,uint256 amount)");

  /// @dev EIP-712 typehash for LimitBuyOrder
  bytes32 public constant LIMIT_BUY_ORDER_TYPEHASH =
    keccak256(
      "LimitBuyOrder("
      "address owner,"
      "address targetVault,"
      "address pricingAsset,"
      "uint256 minTriggerPriceD18,"
      "uint256 maxTriggerPriceD18,"
      "uint16 slippageToleranceBps"
      ")"
    );

  /// @dev The witness type string for Permit2
  /// @notice This is appended to the Permit2 stub to form the full type
  string public constant WITNESS_TYPE_STRING =
    "LimitBuyOrder witness)"
    "LimitBuyOrder("
    "address owner,"
    "address targetVault,"
    "address pricingAsset,"
    "uint256 minTriggerPriceD18,"
    "uint256 maxTriggerPriceD18,"
    "uint16 slippageToleranceBps"
    ")"
    "TokenPermissions(address token,uint256 amount)";

  /// @dev EIP-712 typehash for PermitWitnessTransferFrom with LimitBuyOrder witness
  /// @notice This MUST match exactly what Permit2 computes internally
  bytes32 public constant PERMIT_WITNESS_TRANSFER_FROM_TYPEHASH =
    keccak256(
      "PermitWitnessTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline,"
      "LimitBuyOrder witness)"
      "LimitBuyOrder(address owner,address targetVault,address pricingAsset,uint256 minTriggerPriceD18,uint256 maxTriggerPriceD18,uint16 slippageToleranceBps)"
      "TokenPermissions(address token,uint256 amount)"
    );

  /// @dev EIP-712 domain typehash
  bytes32 public constant EIP712_DOMAIN_TYPEHASH =
    keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

  // ============ EIP-712 Hashing Functions ============

  /// @dev Hash a LimitBuyOrder struct according to EIP-712
  function hashLimitBuyOrder(LimitBuyOrder memory order) internal pure returns (bytes32) {
    return
      keccak256(
        abi.encode(
          LIMIT_BUY_ORDER_TYPEHASH,
          order.owner,
          order.targetVault,
          order.pricingAsset,
          order.minTriggerPriceD18,
          order.maxTriggerPriceD18,
          order.slippageToleranceBps
        )
      );
  }

  /// @dev Hash a TokenPermissions struct according to EIP-712
  function hashTokenPermissions(TokenPermissions memory p) internal pure returns (bytes32) {
    return keccak256(abi.encode(TOKEN_PERMISSIONS_TYPEHASH, p.token, p.amount));
  }

  /// @dev Hash a PermitWitnessTransferFrom struct according to EIP-712
  function hashPermit(PermitWitnessTransferFrom memory p) internal pure returns (bytes32) {
    return
      keccak256(
        abi.encode(
          PERMIT_WITNESS_TRANSFER_FROM_TYPEHASH,
          hashTokenPermissions(p.permitted),
          p.spender,
          p.nonce,
          p.deadline,
          hashLimitBuyOrder(p.witness)
        )
      );
  }

  /// @dev Compute the EIP-712 domain separator
  function domainSeparator(EIP712Domain memory d) internal pure returns (bytes32) {
    return keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, keccak256(bytes(d.name)), d.chainId, d.verifyingContract));
  }

  /// @dev Compute the final EIP-712 digest that gets signed
  /// @param d The complete typed data structure
  /// @return The EIP-712 hash that should be signed
  function getDigest(LimitBuyTypedData memory d) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked("\x19\x01", domainSeparator(d.domain), hashPermit(d.message)));
  }
}
