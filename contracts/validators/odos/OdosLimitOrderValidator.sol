// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {IHasAssetInfo} from "../../interfaces/IHasAssetInfo.sol";
import {IHasSupportedAsset} from "../../interfaces/IHasSupportedAsset.sol";
import {IPoolManagerLogic} from "../../interfaces/IPoolManagerLogic.sol";
import {IPermit2} from "../../interfaces/permit2/IPermit2.sol";
import {IERC20Extended} from "../../interfaces/IERC20Extended.sol";
import {OdosLimitOrderTypeHashLib} from "./OdosLimitOrderTypeHashLib.sol";

/// @title OdosLimitOrderValidator
/// @notice Library for validating Odos limit order EIP-712 typed data
/// @dev Odos limit orders use Permit2's PermitWitnessTransferFrom pattern.
///      This library decodes the full typed data, validates it against dHEDGE pool rules,
///      and recomputes the EIP-712 hash to ensure integrity.
///
///      Validation checks:
///      - Domain name is "Permit2"
///      - Chain ID matches current chain
///      - Verifying contract matches configured Permit2 address
///      - Spender matches configured Odos router address
///      - Input and output tokens are supported by the pool
///      - Order rate is not significantly worse than current oracle prices (prevents immediate-loss orders)
///
///      Rate Protection:
///      Orders where the pool would receive significantly less value than it gives (based on oracle prices)
///      are rejected. This prevents malicious or erroneous orders that could be immediately filled at a loss.
///      "Take profit" orders (asking for more than market) are always allowed as they can only fill when
///      market moves in the pool's favor.
library OdosLimitOrderValidator {
  /// @notice Thrown when the EIP-712 domain name is not "Permit2"
  error DomainNameMismatch();
  /// @notice Thrown when the EIP-712 domain chain ID doesn't match the current chain
  error DomainChainMismatch();
  /// @notice Thrown when the EIP-712 verifying contract doesn't match the configured Permit2 address
  error DomainVerifyingContractMismatch();

  /// @notice Thrown when the spender doesn't match the configured Odos router address
  error SpenderMismatch();
  /// @notice Thrown when the permitted token doesn't match the order input token
  error InputTokenMismatch();
  /// @notice Thrown when the permitted amount doesn't match the order input amount
  error InputAmountMismatch();
  /// @notice Thrown when the order expiry doesn't match the permit deadline
  error ExpiryMismatch();
  /// @notice Thrown when the order has already expired
  error OrderExpired();
  /// @notice Thrown when the Permit2 nonce has already been used
  error NonceAlreadyUsed();
  /// @notice Thrown when the input token is not supported by the pool
  error UnsupportedInputToken();
  /// @notice Thrown when the output token is not supported by the pool
  error UnsupportedOutputToken();
  /// @notice Thrown when the order rate is too unfavorable compared to oracle price
  /// @dev This prevents immediate-loss orders that could drain the pool
  error OrderRateTooUnfavorable();

  /// @notice Configuration for Odos limit order validation
  /// @dev Set by the owner via TypedStructuredDataValidator.setValidationConfig()
  /// @param verifyingContract The Permit2 contract address for this chain
  /// @param spender The Odos limit order router address that will execute orders
  /// @param maxUnfavorableDeviationBps Maximum allowed unfavorable deviation from oracle rate in basis points
  ///        (e.g., 100 = 1%). Orders worse than this are rejected to prevent immediate losses.
  struct OdosLimitOrderValidationConfig {
    address verifyingContract; // Permit2 address
    address spender; // Odos limit order router
    uint256 maxUnfavorableDeviationBps; // Max unfavorable deviation in basis points (e.g., 100 = 1%)
    // Future: could add referral validation
    // uint64 referralCode;
    // uint64 referralFee;
    // address referralFeeRecipient;
  }

  /// @dev Pre-computed keccak256 hash of "Permit2" for gas-efficient domain name validation
  bytes32 private constant PERMIT2_NAME_HASH = keccak256("Permit2");

  /// @dev Basis points denominator (100% = 10000)
  uint256 private constant BASIS_POINTS = 10000;

  // ============ EIP-712 Hashing Functions ============

  /// @dev Hash a TokenInfo struct according to EIP-712
  function hashTokenInfo(OdosLimitOrderTypeHashLib.TokenInfo memory t) internal pure returns (bytes32) {
    return keccak256(abi.encode(OdosLimitOrderTypeHashLib.TOKEN_INFO_TYPEHASH, t.tokenAddress, t.tokenAmount));
  }

  /// @dev Hash a LimitOrder struct according to EIP-712
  function hashLimitOrder(OdosLimitOrderTypeHashLib.LimitOrder memory o) internal pure returns (bytes32) {
    return
      keccak256(
        abi.encode(
          OdosLimitOrderTypeHashLib.LIMIT_ORDER_TYPEHASH,
          hashTokenInfo(o.input),
          hashTokenInfo(o.output),
          o.expiry,
          o.salt,
          o.referralCode,
          o.referralFee,
          o.referralFeeRecipient,
          o.partiallyFillable
        )
      );
  }

  /// @dev Hash a TokenPermissions struct according to EIP-712
  function hashTokenPermissions(OdosLimitOrderTypeHashLib.TokenPermissions memory p) internal pure returns (bytes32) {
    return keccak256(abi.encode(OdosLimitOrderTypeHashLib.TOKEN_PERMISSIONS_TYPEHASH, p.token, p.amount));
  }

  /// @dev Hash a PermitWitnessTransferFrom struct according to EIP-712
  function hashPermit(OdosLimitOrderTypeHashLib.PermitWitnessTransferFrom memory p) internal pure returns (bytes32) {
    return
      keccak256(
        abi.encode(
          OdosLimitOrderTypeHashLib.PERMIT_WITNESS_TRANSFER_FROM_TYPEHASH,
          hashTokenPermissions(p.permitted),
          p.spender,
          p.nonce,
          p.deadline,
          hashLimitOrder(p.witness)
        )
      );
  }

  /// @dev Compute the EIP-712 domain separator
  function domainSeparator(OdosLimitOrderTypeHashLib.EIP712Domain memory d) internal pure returns (bytes32) {
    return
      keccak256(
        abi.encode(
          OdosLimitOrderTypeHashLib.EIP712_DOMAIN_TYPEHASH,
          keccak256(bytes(d.name)),
          d.chainId,
          d.verifyingContract
        )
      );
  }

  /// @dev Compute the final EIP-712 digest that gets signed
  /// @param d The complete typed data structure
  /// @return The EIP-712 hash that should be signed
  function getDigest(OdosLimitOrderTypeHashLib.OdosLimitOrderTypedData memory d) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked("\x19\x01", domainSeparator(d.domain), hashPermit(d.message)));
  }

  // ============ Validation Functions ============

  /// @dev Verify the EIP-712 domain is valid for Permit2 on this chain
  /// @param domain The domain from the typed data
  /// @param config The validation configuration containing expected Permit2 address
  function verifyDomain(
    OdosLimitOrderTypeHashLib.EIP712Domain memory domain,
    OdosLimitOrderValidationConfig memory config
  ) internal view {
    // Must be signed for Permit2 (compare against pre-computed hash for gas efficiency)
    if (keccak256(bytes(domain.name)) != PERMIT2_NAME_HASH) {
      revert DomainNameMismatch();
    }

    // Must be for the current chain (prevents cross-chain replay)
    if (domain.chainId != block.chainid) {
      revert DomainChainMismatch();
    }

    // Must be for the correct Permit2 contract
    if (domain.verifyingContract != config.verifyingContract) {
      revert DomainVerifyingContractMismatch();
    }
  }

  /// @dev Verify the message contents are safe for the dHEDGE pool
  /// @param message The PermitWitnessTransferFrom message from the typed data
  /// @param config The validation configuration containing expected spender
  /// @param poolLogic The pool's PoolLogic address (for Permit2 nonce check)
  /// @param poolManagerLogic The pool's PoolManagerLogic address for asset validation
  function verifyMessage(
    OdosLimitOrderTypeHashLib.PermitWitnessTransferFrom memory message,
    OdosLimitOrderValidationConfig memory config,
    address poolLogic,
    address poolManagerLogic
  ) internal view {
    // Spender must be the Odos limit order router (prevents approval to malicious contracts)
    if (message.spender != config.spender) {
      revert SpenderMismatch();
    }

    // Sanity check: permitted token must match order input token
    if (message.permitted.token != message.witness.input.tokenAddress) {
      revert InputTokenMismatch();
    }

    // Sanity check: permitted amount must match order input amount
    if (message.permitted.amount != message.witness.input.tokenAmount) {
      revert InputAmountMismatch();
    }

    // Sanity check: order expiry must match permit deadline
    if (message.deadline != message.witness.expiry) {
      revert ExpiryMismatch();
    }

    // Order must not be already expired
    if (message.witness.expiry <= block.timestamp) {
      revert OrderExpired();
    }

    // Nonce must not be already used in Permit2
    // This prevents submitting orders that would fail on execution anyway
    if (_isNonceUsed(config.verifyingContract, poolLogic, message.nonce)) {
      revert NonceAlreadyUsed();
    }

    // Input token (sell token) must be supported by the pool
    if (!IHasSupportedAsset(poolManagerLogic).isSupportedAsset(message.witness.input.tokenAddress)) {
      revert UnsupportedInputToken();
    }

    // Output token (buy token) must be supported by the pool
    if (!IHasSupportedAsset(poolManagerLogic).isSupportedAsset(message.witness.output.tokenAddress)) {
      revert UnsupportedOutputToken();
    }

    // Validate order rate is not too unfavorable compared to current oracle prices.
    // This prevents immediate-loss orders that could be filled right away at a loss to the pool.
    // Orders at better-than-market rates (take profit, buy dip) are always allowed.
    _verifyOrderRate(message.witness, config, poolManagerLogic);
  }

  /// @dev Verify the order rate is not significantly worse than current oracle prices
  /// @param order The limit order witness data containing input/output token info
  /// @param config The validation configuration containing maxUnfavorableDeviationBps
  /// @param poolManagerLogic The pool's PoolManagerLogic address to get factory for oracle access
  function _verifyOrderRate(
    OdosLimitOrderTypeHashLib.LimitOrder memory order,
    OdosLimitOrderValidationConfig memory config,
    address poolManagerLogic
  ) private view {
    address poolFactory = IPoolManagerLogic(poolManagerLogic).factory();

    uint256 inputPriceD18 = IHasAssetInfo(poolFactory).getAssetPrice(order.input.tokenAddress);
    uint256 outputPriceD18 = IHasAssetInfo(poolFactory).getAssetPrice(order.output.tokenAddress);

    uint8 inputDecimals = IERC20Extended(order.input.tokenAddress).decimals();
    uint8 outputDecimals = IERC20Extended(order.output.tokenAddress).decimals();

    // To avoid precision loss, we use cross-multiplication:
    // outputValueUSD >= inputValueUSD * (BASIS_POINTS - maxUnfavorableDeviationBps) / BASIS_POINTS
    //
    // Rearranging to avoid division until the end:
    // outputAmount * outputPriceD18 * 10^inputDecimals * BASIS_POINTS >=
    // inputAmount * inputPriceD18 * 10^outputDecimals * (BASIS_POINTS - maxUnfavorableDeviationBps)
    uint256 outputSide = order.output.tokenAmount * outputPriceD18 * (10 ** inputDecimals) * BASIS_POINTS;
    uint256 inputSide = order.input.tokenAmount *
      inputPriceD18 *
      (10 ** outputDecimals) *
      (BASIS_POINTS - config.maxUnfavorableDeviationBps);

    if (outputSide < inputSide) {
      revert OrderRateTooUnfavorable();
    }
  }

  /// @notice Check if a Permit2 nonce has already been used
  /// @dev Permit2 uses a bitmap pattern for gas-efficient nonce tracking.
  ///      Instead of storing each nonce separately (expensive), it packs 256 nonces
  ///      into a single uint256 storage slot:
  ///        - Word 0: tracks nonces 0-255
  ///        - Word 1: tracks nonces 256-511
  ///        - Word N: tracks nonces (N*256) to (N*256 + 255)
  ///
  ///      For a given nonce:
  ///        - wordPos = nonce / 256 (which word contains it)
  ///        - bitPos = nonce % 256 (which bit within that word)
  ///
  ///      Bit shifts are used for efficiency: >> 8 divides by 256, & 0xFF is modulo 256.
  /// @param permit2 The Permit2 contract address
  /// @param owner The address that owns the nonce (the pool)
  /// @param nonce The nonce to check
  /// @return True if the nonce has been used, false otherwise
  function _isNonceUsed(address permit2, address owner, uint256 nonce) internal view returns (bool) {
    // Divide by 256 to get which storage word contains this nonce
    uint256 wordPos = nonce >> 8;
    // Modulo 256 to get which bit within that word (0-255)
    uint256 bitPos = nonce & 0xFF;
    // Fetch the 256-bit bitmap for this owner at the calculated word position
    uint256 bitmap = IPermit2(permit2).nonceBitmap(owner, wordPos);
    // Check if the specific bit is set (1 = used, 0 = unused)
    return (bitmap & (1 << bitPos)) != 0;
  }

  /// @notice Validate an Odos limit order and return its EIP-712 hash along with order details
  /// @dev This is the main entry point called by TypedStructuredDataValidator.
  ///      It decodes the typed data, validates all fields, and returns the hash
  ///      that will be stored as approved for ERC-1271 signature verification.
  /// @param orderData ABI-encoded OdosLimitOrderTypedData
  /// @param configData ABI-encoded OdosLimitOrderValidationConfig
  /// @param poolLogic The pool's PoolLogic address (for Permit2 nonce check)
  /// @param poolManagerLogic The pool's PoolManagerLogic address
  /// @return hash The EIP-712 digest that the manager should sign
  /// @return inputToken The input token address (token being sold)
  /// @return outputToken The output token address (token being bought)
  /// @return expiry The order expiration timestamp
  function validate(
    bytes calldata orderData,
    bytes memory configData,
    address poolLogic,
    address poolManagerLogic
  ) internal view returns (bytes32 hash, address inputToken, address outputToken, uint256 expiry) {
    // Decode the full typed data structure
    OdosLimitOrderTypeHashLib.OdosLimitOrderTypedData memory typedData = abi.decode(
      orderData,
      (OdosLimitOrderTypeHashLib.OdosLimitOrderTypedData)
    );
    OdosLimitOrderValidationConfig memory config = abi.decode(configData, (OdosLimitOrderValidationConfig));

    // Validate EIP-712 domain (Permit2 contract, correct chain)
    verifyDomain(typedData.domain, config);

    // Validate message contents (spender, tokens are supported)
    verifyMessage(typedData.message, config, poolLogic, poolManagerLogic);

    // Compute the EIP-712 hash
    // This hash will be stored in validatedHashes and checked during isValidSignature
    hash = getDigest(typedData);

    // Extract token addresses and expiry for active order tracking
    inputToken = typedData.message.witness.input.tokenAddress;
    outputToken = typedData.message.witness.output.tokenAddress;
    expiry = typedData.message.witness.expiry;
  }
}
