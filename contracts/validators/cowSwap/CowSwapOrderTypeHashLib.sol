// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;

/// @title CowSwapOrderTypeHashLib
/// @notice Library containing type definitions and EIP-712 type hashes for CoWSwap (GPv2) orders
/// @dev CoWSwap orders use the GPv2Order.Data structure defined in the GPv2Settlement contract.
library CowSwapOrderTypeHashLib {
  /// @notice CoWSwap (GPv2) order structure
  /// @dev This matches the GPv2Order.Data struct from the CoWSwap settlement contract
  /// @param sellToken ERC-20 token to sell
  /// @param buyToken ERC-20 token to buy
  /// @param receiver Address to receive the bought tokens (address(0) means order owner)
  /// @param sellAmount Amount of sellToken to sell in wei
  /// @param buyAmount Amount of buyToken to buy in wei
  /// @param validTo UNIX timestamp (in seconds) until which the order is valid
  /// @param appData Arbitrary 32-byte data for off-chain metadata (referrals, etc.)
  /// @param feeAmount Amount of fees paid in sellToken wei (protocol fees)
  /// @param kind Order kind: keccak256("sell") or keccak256("buy")
  /// @param partiallyFillable Whether the order can be partially filled
  /// @param sellTokenBalance Balance source for sell token: keccak256("erc20")
  /// @param buyTokenBalance Balance destination for buy token: keccak256("erc20")
  struct GPv2Order {
    address sellToken;
    address buyToken;
    address receiver;
    uint256 sellAmount;
    uint256 buyAmount;
    uint32 validTo;
    bytes32 appData;
    uint256 feeAmount;
    bytes32 kind;
    bool partiallyFillable;
    bytes32 sellTokenBalance;
    bytes32 buyTokenBalance;
  }

  /// @notice EIP-712 domain structure for CoWSwap
  /// @param name Domain name (should be "Gnosis Protocol")
  /// @param version Domain version (should be "v2")
  /// @param chainId The chain ID
  /// @param verifyingContract The GPv2Settlement contract address
  struct EIP712Domain {
    string name;
    string version;
    uint256 chainId;
    address verifyingContract;
  }

  /// @notice Complete EIP-712 typed data structure for CoWSwap orders
  /// @param domain The EIP-712 domain
  /// @param order The GPv2 order data
  struct CowSwapTypedData {
    EIP712Domain domain;
    GPv2Order order;
  }

  // ============ EIP-712 Type Hashes ============
  // These match the values used by the GPv2Settlement contract

  /// @dev EIP-712 typehash for GPv2Order
  bytes32 public constant ORDER_TYPE_HASH =
    keccak256(
      "Order("
      "address sellToken,"
      "address buyToken,"
      "address receiver,"
      "uint256 sellAmount,"
      "uint256 buyAmount,"
      "uint32 validTo,"
      "bytes32 appData,"
      "uint256 feeAmount,"
      "string kind,"
      "bool partiallyFillable,"
      "string sellTokenBalance,"
      "string buyTokenBalance"
      ")"
    );

  /// @dev EIP-712 domain typehash
  bytes32 public constant EIP712_DOMAIN_TYPEHASH =
    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

  /// @dev Marker value for a sell order
  bytes32 public constant KIND_SELL = keccak256("sell");

  /// @dev Marker value for a buy order
  bytes32 public constant KIND_BUY = keccak256("buy");

  /// @dev Marker value for ERC20 token balance
  bytes32 public constant BALANCE_ERC20 = keccak256("erc20");

  // ============ EIP-712 Hashing Functions ============

  /// @dev Hash a GPv2Order struct according to EIP-712
  /// @notice The order struct already contains pre-hashed values for kind and balance types
  function hashOrder(GPv2Order memory order) internal pure returns (bytes32) {
    return
      keccak256(
        abi.encode(
          ORDER_TYPE_HASH,
          order.sellToken,
          order.buyToken,
          order.receiver,
          order.sellAmount,
          order.buyAmount,
          order.validTo,
          order.appData,
          order.feeAmount,
          order.kind,
          order.partiallyFillable,
          order.sellTokenBalance,
          order.buyTokenBalance
        )
      );
  }

  /// @dev Compute the EIP-712 domain separator for CoWSwap
  function domainSeparator(EIP712Domain memory domain) internal pure returns (bytes32) {
    return
      keccak256(
        abi.encode(
          EIP712_DOMAIN_TYPEHASH,
          keccak256(bytes(domain.name)),
          keccak256(bytes(domain.version)),
          domain.chainId,
          domain.verifyingContract
        )
      );
  }

  /// @dev Compute the final EIP-712 digest that gets signed
  /// @param data The complete typed data structure
  /// @return The EIP-712 hash that should be signed
  function getDigest(CowSwapTypedData memory data) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked("\x19\x01", domainSeparator(data.domain), hashOrder(data.order)));
  }
}
