// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {IHasAssetInfo} from "../../interfaces/IHasAssetInfo.sol";
import {IHasSupportedAsset} from "../../interfaces/IHasSupportedAsset.sol";
import {IPoolManagerLogic} from "../../interfaces/IPoolManagerLogic.sol";
import {IERC20Extended} from "../../interfaces/IERC20Extended.sol";
import {CowSwapOrderTypeHashLib} from "./CowSwapOrderTypeHashLib.sol";

/// @title CowSwapOrderValidator
/// @notice Library for validating CoWSwap (GPv2) order EIP-712 typed data
/// @dev CoWSwap orders are signed directly using EIP-712 without Permit2.
///      This library decodes the full typed data, validates it against dHEDGE pool rules,
///      and recomputes the EIP-712 hash to ensure integrity.
library CowSwapOrderValidator {
  // ============ Domain Validation Errors ============

  /// @notice Thrown when the EIP-712 domain name is not "Gnosis Protocol"
  error DomainNameMismatch();
  /// @notice Thrown when the EIP-712 domain version is not "v2"
  error DomainVersionMismatch();
  /// @notice Thrown when the EIP-712 domain chain ID doesn't match the current chain
  error DomainChainMismatch();
  /// @notice Thrown when the EIP-712 verifying contract doesn't match GPv2Settlement
  error DomainVerifyingContractMismatch();

  // ============ Order Validation Errors ============

  /// @notice Thrown when the receiver is not the pool or address(0)
  error InvalidReceiver();
  /// @notice Thrown when the sell token is not supported by the pool
  error UnsupportedSellToken();
  /// @notice Thrown when the buy token is not supported by the pool
  error UnsupportedBuyToken();
  /// @notice Thrown when sellTokenBalance is not "erc20"
  error InvalidSellTokenBalance();
  /// @notice Thrown when buyTokenBalance is not "erc20"
  error InvalidBuyTokenBalance();
  /// @notice Thrown when the order kind is not "sell" or "buy"
  error InvalidOrderKind();
  /// @notice Thrown when the order has already expired
  error OrderExpired();
  /// @notice Thrown when the order rate is too unfavorable compared to oracle price
  error OrderRateTooUnfavorable();
  /// @notice Thrown when feeAmount is non-zero (not currently supported)
  /// @dev If non-zero feeAmount support is needed, include it in rate check:
  ///      effectiveSellAmount = sellAmount + feeAmount (fee is always from sellToken)
  error NonZeroFeeAmount();

  /// @notice Configuration for CoWSwap order validation
  /// @dev Set by the owner via TypedStructuredDataValidator.setValidationConfig()
  /// @param gpv2Settlement The GPv2Settlement contract address (domain verifying contract)
  /// @param maxUnfavorableDeviationBps Maximum allowed unfavorable deviation from oracle rate in basis points
  struct CowSwapValidationConfig {
    address gpv2Settlement;
    uint256 maxUnfavorableDeviationBps;
  }

  /// @dev Pre-computed keccak256 hash of "Gnosis Protocol" for gas-efficient domain name validation
  bytes32 private constant GNOSIS_PROTOCOL_NAME_HASH = keccak256("Gnosis Protocol");

  /// @dev Pre-computed keccak256 hash of "v2" for gas-efficient domain version validation
  bytes32 private constant DOMAIN_VERSION_HASH = keccak256("v2");

  /// @dev Basis points denominator (100% = 10000)
  uint256 private constant BASIS_POINTS = 10000;

  // ============ Validation Functions ============

  /// @dev Verify the EIP-712 domain is valid for CoWSwap on this chain
  /// @param domain The domain from the typed data
  /// @param config The validation configuration containing expected GPv2Settlement address
  function verifyDomain(
    CowSwapOrderTypeHashLib.EIP712Domain memory domain,
    CowSwapValidationConfig memory config
  ) internal view {
    if (keccak256(bytes(domain.name)) != GNOSIS_PROTOCOL_NAME_HASH) {
      revert DomainNameMismatch();
    }

    if (keccak256(bytes(domain.version)) != DOMAIN_VERSION_HASH) {
      revert DomainVersionMismatch();
    }

    // Must be for the current chain (prevents cross-chain replay)
    if (domain.chainId != block.chainid) {
      revert DomainChainMismatch();
    }

    // Must be for the correct GPv2Settlement contract
    if (domain.verifyingContract != config.gpv2Settlement) {
      revert DomainVerifyingContractMismatch();
    }
  }

  /// @dev Verify the order contents are safe for the dHEDGE pool
  /// @param order The GPv2Order from the typed data
  /// @param poolLogic The pool's PoolLogic address (order owner and receiver)
  /// @param poolManagerLogic The pool's PoolManagerLogic address for asset validation
  function verifyOrder(
    CowSwapOrderTypeHashLib.GPv2Order memory order,
    address poolLogic,
    address poolManagerLogic
  ) internal view {
    // Receiver must be the pool or address(0) (which means owner receives)
    // However, we don't allow address(0) for better clarity and due to no use case
    if (order.receiver != poolLogic) {
      revert InvalidReceiver();
    }

    // Order kind must be valid (sell or buy)
    if (order.kind != CowSwapOrderTypeHashLib.KIND_SELL && order.kind != CowSwapOrderTypeHashLib.KIND_BUY) {
      revert InvalidOrderKind();
    }

    // Only allow ERC20 balance types (no Balancer vault integration)
    if (order.sellTokenBalance != CowSwapOrderTypeHashLib.BALANCE_ERC20) {
      revert InvalidSellTokenBalance();
    }
    if (order.buyTokenBalance != CowSwapOrderTypeHashLib.BALANCE_ERC20) {
      revert InvalidBuyTokenBalance();
    }

    // feeAmount must be zero - CoWSwap v2 has protocol fees handled separately
    // If non-zero feeAmount becomes needed, include in rate check: effectiveSell = sellAmount + feeAmount
    if (order.feeAmount != 0) {
      revert NonZeroFeeAmount();
    }

    // Order must not be expired
    if (order.validTo <= block.timestamp) {
      revert OrderExpired();
    }

    // Sell token must be supported by the pool
    if (!IHasSupportedAsset(poolManagerLogic).isSupportedAsset(order.sellToken)) {
      revert UnsupportedSellToken();
    }

    // Buy token must be supported by the pool
    if (!IHasSupportedAsset(poolManagerLogic).isSupportedAsset(order.buyToken)) {
      revert UnsupportedBuyToken();
    }
  }

  /// @dev Verify the order rate is not significantly worse than current oracle prices
  /// @param order The GPv2 order containing token and amount info
  /// @param config The validation configuration containing maxUnfavorableDeviationBps
  /// @param poolManagerLogic The pool's PoolManagerLogic address to get factory for oracle access
  function verifyOrderRate(
    CowSwapOrderTypeHashLib.GPv2Order memory order,
    CowSwapValidationConfig memory config,
    address poolManagerLogic
  ) internal view {
    address poolFactory = IPoolManagerLogic(poolManagerLogic).factory();

    uint256 sellPriceD18 = IHasAssetInfo(poolFactory).getAssetPrice(order.sellToken);
    uint256 buyPriceD18 = IHasAssetInfo(poolFactory).getAssetPrice(order.buyToken);

    uint8 sellDecimals = IERC20Extended(order.sellToken).decimals();
    uint8 buyDecimals = IERC20Extended(order.buyToken).decimals();

    // For both sell and buy order kinds:
    // - Pool gives up to sellAmount of sellToken
    // - Pool receives at least buyAmount of buyToken
    //
    // We check that what we receive is worth at least (1 - deviation) of what we give.

    // Calculate USD values (prices are 18 decimals)
    uint256 sellValueUSD = (order.sellAmount * sellPriceD18) / (10 ** sellDecimals);
    uint256 buyValueUSD = (order.buyAmount * buyPriceD18) / (10 ** buyDecimals);

    // Minimum acceptable value = sellValue * (100% - maxDeviation%)
    uint256 minAcceptableBuyValue = (sellValueUSD * (BASIS_POINTS - config.maxUnfavorableDeviationBps)) / BASIS_POINTS;

    if (buyValueUSD < minAcceptableBuyValue) {
      revert OrderRateTooUnfavorable();
    }
  }

  /// @notice Validate a CoWSwap order and return its EIP-712 hash along with order details
  /// @dev This is the main entry point called by TypedStructuredDataValidator.
  ///      It decodes the typed data, validates all fields, and returns the hash
  ///      that will be stored as approved for further verification.
  /// @param orderData ABI-encoded CowSwapTypedData
  /// @param configData ABI-encoded CowSwapValidationConfig
  /// @param poolLogic The pool's PoolLogic address (order owner)
  /// @param poolManagerLogic The pool's PoolManagerLogic address
  /// @return hash The EIP-712 digest that the manager should sign
  /// @return sellToken The sell token address (token being sold)
  /// @return buyToken The buy token address (token being bought)
  /// @return expiry The order expiration timestamp
  /// @return targetFillAmount The amount that indicates full fill (sellAmount for sell, buyAmount for buy)
  function validate(
    bytes calldata orderData,
    bytes memory configData,
    address poolLogic,
    address poolManagerLogic
  )
    internal
    view
    returns (bytes32 hash, address sellToken, address buyToken, uint256 expiry, uint256 targetFillAmount)
  {
    // Decode the full typed data structure
    CowSwapOrderTypeHashLib.CowSwapTypedData memory typedData = abi.decode(
      orderData,
      (CowSwapOrderTypeHashLib.CowSwapTypedData)
    );
    CowSwapValidationConfig memory config = abi.decode(configData, (CowSwapValidationConfig));

    // Validate EIP-712 domain (GPv2Settlement contract, correct chain)
    verifyDomain(typedData.domain, config);

    // Validate order contents (receiver, tokens, balance types, expiry)
    verifyOrder(typedData.order, poolLogic, poolManagerLogic);

    // Validate order rate is not too unfavorable compared to current oracle prices
    verifyOrderRate(typedData.order, config, poolManagerLogic);

    // Compute the EIP-712 hash
    // This hash will be stored in validatedHashes
    hash = CowSwapOrderTypeHashLib.getDigest(typedData);

    // Extract token addresses and expiry for active order tracking
    sellToken = typedData.order.sellToken;
    buyToken = typedData.order.buyToken;
    expiry = typedData.order.validTo;

    // Determine target fill amount based on order kind
    // For sell orders: filledAmount tracks sellAmount
    // For buy orders: filledAmount tracks buyAmount
    if (typedData.order.kind == CowSwapOrderTypeHashLib.KIND_SELL) {
      targetFillAmount = typedData.order.sellAmount;
    } else {
      targetFillAmount = typedData.order.buyAmount;
    }
  }
}
