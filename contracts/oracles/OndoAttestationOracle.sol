// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {ECDSA} from "@openzeppelin/v5/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/v5/contracts/utils/cryptography/MessageHashUtils.sol";

import {OwnableUpgradeable} from "@openzeppelin/v5/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {ICommonErrors} from "../interfaces/ICommonErrors.sol";
import {IGMTokenManager} from "../interfaces/ondo/IGMTokenManager.sol";
import {IOndoAttestationOracle} from "../interfaces/ondo/IOndoAttestationOracle.sol";
import {IOndoSanityCheckOracle} from "../interfaces/ondo/IOndoSanityCheckOracle.sol";

/// @title OndoAttestationOracle
/// @notice Stores Ondo GM token prices verified via EIP-712 attestation signatures.
///         Returns the fresher price between the stored attestation and Ondo's on-chain sanity check oracle.
contract OndoAttestationOracle is OwnableUpgradeable, ICommonErrors, IOndoAttestationOracle {
  // ========== STRUCTS ==========

  struct ProofConfig {
    uint256 maxProofAge;
    uint256 sanityDeviationBps;
    uint256 minQuoteValue;
    uint256 maxQuoteValue;
  }

  struct AttestedPrice {
    uint256 price;
    uint256 updatedAt;
    uint256 expiration;
  }

  // ========== STATE ==========

  IGMTokenManager public gmTokenManager;
  ProofConfig public proofConfig;
  bytes32 public allowedUserId; // optional additional security; bytes32(0) disables userId validation

  mapping(address gmToken => AttestedPrice) public attestedPrices;

  // ========== CONSTANTS ==========

  uint256 public constant BPS_DENOMINATOR = 10_000;
  /// @notice Maximum allowed skew between a quote's expiration and block.timestamp (both directions).
  uint256 public constant MAX_QUOTE_EXPIRY_SKEW = 1 minutes;

  bytes32 public constant QUOTE_TYPEHASH =
    keccak256(
      "Quote(uint256 chainId,uint256 attestationId,bytes32 userId,address asset,uint256 price,uint256 quantity,uint256 expiration,uint8 side,bytes32 additionalData)"
    );

  // ========== EVENTS ==========

  event PriceUpdated(address indexed gmToken, uint256 price, uint256 updatedAt);
  event GmTokenManagerUpdated(IGMTokenManager gmTokenManager);
  event AllowedUserIdUpdated(bytes32 allowedUserId);
  event ProofConfigUpdated();

  // ========== ERRORS ==========

  error ZeroValue(string varName);
  error InvalidProofConfig(string varName);
  error ArrayLengthMismatch();
  error InvalidChainId();
  error QuoteValueOutOfRange();
  error InvalidAttestationSignature();
  error InvalidQuoteSide();
  error SanityCheckDeviationTooLarge();
  error StaleAttestation();
  error QuoteExpirationTooFar();
  error UnauthorizedUserId();
  error NoPriceAvailable();

  // ========== CONSTRUCTOR ==========

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(
    address _owner,
    IGMTokenManager _gmTokenManager,
    bytes32 _allowedUserId,
    ProofConfig calldata _config
  ) external initializer {
    __Ownable_init(_owner);

    if (address(_gmTokenManager) == address(0)) revert ZeroAddress("_gmTokenManager");
    _validateProofConfig(_config);

    gmTokenManager = _gmTokenManager;
    allowedUserId = _allowedUserId;
    proofConfig = _config;
  }

  // ========== EXTERNAL FUNCTIONS ==========

  /// @notice Update attested prices for one or more GM tokens
  /// @dev All inputs are validated via EIP-712 signature from Ondo's attestation signer.
  ///      Only quotes matching the configured allowedUserId are accepted.
  /// @param _quotes Array of Ondo attestation quotes
  /// @param _signatures Array of EIP-712 signatures
  function updatePrices(IGMTokenManager.Quote[] calldata _quotes, bytes[] calldata _signatures) external {
    if (_quotes.length != _signatures.length) revert ArrayLengthMismatch();

    for (uint256 i; i < _quotes.length; ++i) {
      address asset = _quotes[i].asset;

      // Require newer expiration to prevent stale overwrites
      if (_quotes[i].expiration <= attestedPrices[asset].expiration) revert StaleAttestation();

      _verifyAttestation(_quotes[i], _signatures[i]);
      _sanityCheckOnchainOracle(asset, _quotes[i].price);

      attestedPrices[asset] = AttestedPrice({
        price: _quotes[i].price,
        updatedAt: block.timestamp,
        expiration: _quotes[i].expiration
      });

      emit PriceUpdated(asset, _quotes[i].price, block.timestamp);
    }
  }

  // ========== VIEW FUNCTIONS ==========

  /// @notice Get the freshest valid price for a GM token
  /// @dev Compares the stored attested price against Ondo's on-chain sanity check oracle
  ///      and returns whichever was updated more recently.
  /// @param _gmToken The GM token address
  /// @return price The price in 18 decimals
  /// @return updatedAt Timestamp of the returned price
  function getPrice(address _gmToken) external view returns (uint256 price, uint256 updatedAt) {
    // Get sanity oracle price (optional, may not exist)
    uint256 sanityPrice;
    uint256 sanityTime;
    try gmTokenManager.sanityCheckOracle().prices(_gmToken) returns (IOndoSanityCheckOracle.PriceData memory data) {
      if (data.price > 0 && block.timestamp <= uint256(data.lastUpdated) + uint256(data.maxTimeDelay)) {
        sanityPrice = data.price;
        sanityTime = uint256(data.lastUpdated);
      }
      // solhint-disable-next-line no-empty-blocks
    } catch {}

    // Get stored attested price
    AttestedPrice memory attested = attestedPrices[_gmToken];
    bool attestedValid = attested.price > 0 && block.timestamp <= attested.updatedAt + proofConfig.maxProofAge;

    // Return the fresher valid price
    if (sanityPrice == 0 && !attestedValid) revert NoPriceAvailable();
    if (!attestedValid) return (sanityPrice, sanityTime);
    if (sanityPrice == 0) return (attested.price, attested.updatedAt);
    return attested.updatedAt >= sanityTime ? (attested.price, attested.updatedAt) : (sanityPrice, sanityTime);
  }

  // ========== OWNER FUNCTIONS ==========

  /// @notice Update the GM token manager address
  /// @param _gmTokenManager The new GM token manager
  function setGmTokenManager(IGMTokenManager _gmTokenManager) external onlyOwner {
    if (address(_gmTokenManager) == address(0)) revert ZeroAddress("_gmTokenManager");

    gmTokenManager = _gmTokenManager;
    emit GmTokenManagerUpdated(_gmTokenManager);
  }

  /// @notice Update the allowed userId for attestation quotes
  /// @dev Set to bytes32(0) to disable userId validation
  /// @param _allowedUserId The new allowed userId, or bytes32(0) to accept any userId
  function setAllowedUserId(bytes32 _allowedUserId) external onlyOwner {
    allowedUserId = _allowedUserId;
    emit AllowedUserIdUpdated(_allowedUserId);
  }

  /// @notice Update the proof verification configuration
  /// @param _config The new proof configuration
  function setProofConfig(ProofConfig calldata _config) external onlyOwner {
    _validateProofConfig(_config);

    proofConfig = _config;
    emit ProofConfigUpdated();
  }

  // ========== INTERNAL ==========

  /// @notice Validate a ProofConfig's bounds before storing it
  function _validateProofConfig(ProofConfig calldata _config) internal pure {
    if (_config.maxProofAge == 0) revert ZeroValue("_config.maxProofAge");
    if (_config.minQuoteValue == 0) revert ZeroValue("_config.minQuoteValue");
    if (_config.maxQuoteValue < _config.minQuoteValue) revert InvalidProofConfig("maxQuoteValue");
    if (_config.sanityDeviationBps == 0 || _config.sanityDeviationBps > BPS_DENOMINATOR)
      revert InvalidProofConfig("sanityDeviationBps");
  }

  /// @notice Verify the Ondo attestation signature and validity
  /// @dev Reads the domain separator and attestation signer directly from the GMTokenManager
  function _verifyAttestation(IGMTokenManager.Quote calldata _quote, bytes calldata _signature) internal view {
    if (_quote.chainId != block.chainid) revert InvalidChainId();
    if (allowedUserId != bytes32(0) && _quote.userId != allowedUserId) revert UnauthorizedUserId();
    if (_quote.side != uint8(IGMTokenManager.QuoteSide.BUY)) revert InvalidQuoteSide();
    if (_quote.expiration > block.timestamp + MAX_QUOTE_EXPIRY_SKEW) revert QuoteExpirationTooFar();
    if (_quote.expiration + MAX_QUOTE_EXPIRY_SKEW < block.timestamp) revert StaleAttestation();

    uint256 quoteValue = (_quote.price * _quote.quantity) / 1e18;
    if (quoteValue < proofConfig.minQuoteValue || quoteValue > proofConfig.maxQuoteValue) revert QuoteValueOutOfRange();

    bytes32 structHash = keccak256(
      abi.encode(
        QUOTE_TYPEHASH,
        _quote.chainId,
        _quote.attestationId,
        _quote.userId,
        _quote.asset,
        _quote.price,
        _quote.quantity,
        _quote.expiration,
        _quote.side,
        _quote.additionalData
      )
    );

    bytes32 domainSeparator = gmTokenManager.getDomainSeparator();

    bytes32 digest = MessageHashUtils.toTypedDataHash(domainSeparator, structHash);
    address recoveredSigner = ECDSA.recover(digest, _signature);

    if (!gmTokenManager.hasRole(gmTokenManager.ATTESTATION_SIGNER_ROLE(), recoveredSigner))
      revert InvalidAttestationSignature();
  }

  /// @notice Sanity check the attestation price against the on-chain oracle
  /// @dev Skips if the sanity oracle is unavailable, has no price, or is stale for the asset
  function _sanityCheckOnchainOracle(address _asset, uint256 _attestationPrice) internal view {
    try gmTokenManager.sanityCheckOracle().prices(_asset) returns (IOndoSanityCheckOracle.PriceData memory data) {
      if (data.price > 0 && block.timestamp <= uint256(data.lastUpdated) + proofConfig.maxProofAge) {
        uint256 deviation;
        uint256 minPrice;
        if (_attestationPrice > data.price) {
          deviation = _attestationPrice - data.price;
          minPrice = data.price;
        } else {
          deviation = data.price - _attestationPrice;
          minPrice = _attestationPrice;
        }
        if ((deviation * BPS_DENOMINATOR) / minPrice > proofConfig.sanityDeviationBps) {
          revert SanityCheckDeviationTooLarge();
        }
      }
      // solhint-disable-next-line no-empty-blocks
    } catch {}
  }
}
