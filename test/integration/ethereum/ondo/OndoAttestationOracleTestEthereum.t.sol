// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/TransparentUpgradeableProxy.sol";

import {IGMTokenManager} from "contracts/interfaces/ondo/IGMTokenManager.sol";
import {IOndoAttestationOracle} from "contracts/interfaces/ondo/IOndoAttestationOracle.sol";
import {OndoAttestationOracleTestSetup} from "test/integration/common/ondo/OndoAttestationOracleTestSetup.t.sol";
import {EthereumSetup} from "test/integration/utils/foundry/chains/EthereumSetup.t.sol";

contract OndoAttestationOracleTestEthereum is OndoAttestationOracleTestSetup, EthereumSetup {
  // GOOGLon used as second token in multi-token tests
  address internal constant GOOGLON = 0xbA47214eDd2bb43099611b208f75E4b42FDcfEDc;

  constructor() EthereumSetup(24875501) OndoAttestationOracleTestSetup() {}

  function setUp() public override(OndoAttestationOracleTestSetup, EthereumSetup) {
    EthereumSetup.setUp();
    OndoAttestationOracleTestSetup.setUp();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Initialization
  // ═══════════════════════════════════════════════════════════════════════

  function test_initialize_setsStateCorrectly() public view {
    // gmTokenManager
    assertEq(address(IOndoAttestationOracle(attestationOracle).gmTokenManager()), GM_TOKEN_MANAGER);

    // owner
    (bool ok1, bytes memory data1) = attestationOracle.staticcall(abi.encodeWithSignature("owner()"));
    require(ok1);
    assertEq(abi.decode(data1, (address)), owner);

    // allowedUserId
    (bool ok2, bytes memory data2) = attestationOracle.staticcall(abi.encodeWithSignature("allowedUserId()"));
    require(ok2);
    assertEq(abi.decode(data2, (bytes32)), ONDO_USER_ID);

    // proofConfig
    (bool ok3, bytes memory data3) = attestationOracle.staticcall(abi.encodeWithSignature("proofConfig()"));
    require(ok3);
    (uint256 maxProofAge, uint256 sanityDeviationBps, uint256 minQuoteValue, uint256 maxQuoteValue) = abi.decode(
      data3,
      (uint256, uint256, uint256, uint256)
    );
    assertEq(maxProofAge, MAX_PROOF_AGE);
    assertEq(sanityDeviationBps, SANITY_DEVIATION_BPS);
    assertEq(minQuoteValue, MIN_QUOTE_VALUE);
    assertEq(maxQuoteValue, MAX_QUOTE_VALUE);
  }

  function test_revert_initialize_twice() public {
    vm.expectRevert("Initializable: contract is already initialized");
    (bool ok, ) = attestationOracle.call(
      abi.encodePacked(
        INITIALIZE_SELECTOR,
        abi.encode(
          owner,
          GM_TOKEN_MANAGER,
          ONDO_USER_ID,
          MAX_PROOF_AGE,
          SANITY_DEVIATION_BPS,
          MIN_QUOTE_VALUE,
          MAX_QUOTE_VALUE
        )
      )
    );
    // If the call didn't revert at the EVM level (low-level call), check ok
    // However, vm.expectRevert should catch it
    ok; // silence unused warning
  }

  function test_revert_initialize_zeroGmTokenManager() public {
    address impl = deployCode("OndoAttestationOracle.sol:OndoAttestationOracle");
    address freshProxy = address(new TransparentUpgradeableProxy(impl, proxyAdmin, ""));
    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("ZeroAddress(string)")), "_gmTokenManager"));
    (bool ok, ) = freshProxy.call(
      abi.encodePacked(
        INITIALIZE_SELECTOR,
        abi.encode(
          owner,
          address(0),
          ONDO_USER_ID,
          MAX_PROOF_AGE,
          SANITY_DEVIATION_BPS,
          MIN_QUOTE_VALUE,
          MAX_QUOTE_VALUE
        )
      )
    );
    ok;
  }

  function test_initialize_zeroAllowedUserId() public {
    address impl = deployCode("OndoAttestationOracle.sol:OndoAttestationOracle");
    address freshProxy = address(new TransparentUpgradeableProxy(impl, proxyAdmin, ""));
    (bool ok, ) = freshProxy.call(
      abi.encodePacked(
        INITIALIZE_SELECTOR,
        abi.encode(
          owner,
          GM_TOKEN_MANAGER,
          bytes32(0),
          MAX_PROOF_AGE,
          SANITY_DEVIATION_BPS,
          MIN_QUOTE_VALUE,
          MAX_QUOTE_VALUE
        )
      )
    );
    require(ok);
    (bool ok2, bytes memory data) = freshProxy.staticcall(abi.encodeWithSignature("allowedUserId()"));
    require(ok2);
    assertEq(abi.decode(data, (bytes32)), bytes32(0));
  }

  function test_revert_initialize_zeroMinQuoteValue() public {
    address impl = deployCode("OndoAttestationOracle.sol:OndoAttestationOracle");
    address freshProxy = address(new TransparentUpgradeableProxy(impl, proxyAdmin, ""));
    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("ZeroValue(string)")), "_config.minQuoteValue"));
    (bool ok, ) = freshProxy.call(
      abi.encodePacked(
        INITIALIZE_SELECTOR,
        abi.encode(
          owner,
          GM_TOKEN_MANAGER,
          ONDO_USER_ID,
          MAX_PROOF_AGE,
          SANITY_DEVIATION_BPS,
          uint256(0),
          MAX_QUOTE_VALUE
        )
      )
    );
    ok;
  }

  function test_revert_initialize_zeroMaxProofAge() public {
    address impl = deployCode("OndoAttestationOracle.sol:OndoAttestationOracle");
    address freshProxy = address(new TransparentUpgradeableProxy(impl, proxyAdmin, ""));
    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("ZeroValue(string)")), "_config.maxProofAge"));
    (bool ok, ) = freshProxy.call(
      abi.encodePacked(
        INITIALIZE_SELECTOR,
        abi.encode(
          owner,
          GM_TOKEN_MANAGER,
          ONDO_USER_ID,
          uint256(0),
          SANITY_DEVIATION_BPS,
          MIN_QUOTE_VALUE,
          MAX_QUOTE_VALUE
        )
      )
    );
    ok;
  }

  function test_revert_initialize_maxQuoteValueBelowMin() public {
    address impl = deployCode("OndoAttestationOracle.sol:OndoAttestationOracle");
    address freshProxy = address(new TransparentUpgradeableProxy(impl, proxyAdmin, ""));
    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("InvalidProofConfig(string)")), "maxQuoteValue"));
    (bool ok, ) = freshProxy.call(
      abi.encodePacked(
        INITIALIZE_SELECTOR,
        abi.encode(
          owner,
          GM_TOKEN_MANAGER,
          ONDO_USER_ID,
          MAX_PROOF_AGE,
          SANITY_DEVIATION_BPS,
          MIN_QUOTE_VALUE,
          MIN_QUOTE_VALUE - 1
        )
      )
    );
    ok;
  }

  function test_revert_initialize_zeroSanityDeviationBps() public {
    address impl = deployCode("OndoAttestationOracle.sol:OndoAttestationOracle");
    address freshProxy = address(new TransparentUpgradeableProxy(impl, proxyAdmin, ""));
    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("InvalidProofConfig(string)")), "sanityDeviationBps"));
    (bool ok, ) = freshProxy.call(
      abi.encodePacked(
        INITIALIZE_SELECTOR,
        abi.encode(owner, GM_TOKEN_MANAGER, ONDO_USER_ID, MAX_PROOF_AGE, uint256(0), MIN_QUOTE_VALUE, MAX_QUOTE_VALUE)
      )
    );
    ok;
  }

  function test_revert_initialize_sanityDeviationBpsAboveDenominator() public {
    address impl = deployCode("OndoAttestationOracle.sol:OndoAttestationOracle");
    address freshProxy = address(new TransparentUpgradeableProxy(impl, proxyAdmin, ""));
    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("InvalidProofConfig(string)")), "sanityDeviationBps"));
    (bool ok, ) = freshProxy.call(
      abi.encodePacked(
        INITIALIZE_SELECTOR,
        abi.encode(
          owner,
          GM_TOKEN_MANAGER,
          ONDO_USER_ID,
          MAX_PROOF_AGE,
          uint256(10_001),
          MIN_QUOTE_VALUE,
          MAX_QUOTE_VALUE
        )
      )
    );
    ok;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // updatePrices — real NFLX attestation (no signature mocking)
  // ═══════════════════════════════════════════════════════════════════════

  /// @notice End-to-end test using real Ondo attestation data for NFLXon.
  ///         Signature is recovered against the real Ondo attestation signer via the real
  ///         GMTokenManager.hasRole check (no mocks on the role check for this signer).
  function test_updatePrices_realNflxAttestation_succeeds() public {
    // Real NFLX attestation from Ondo (attestationId: 12088645379121812514437369881650129103)
    bytes32 realNflxUserId = 0x474d000000000000b50d13795402932300000000000000000000000000000000;
    uint256 realExpiration = 1776140349;
    uint256 realPrice = 1033322403000000000000; // $1033.322403

    // The initializer set allowedUserId to ONDO_USER_ID. Update it to the real NFLX userId.
    vm.prank(owner);
    _callSetAllowedUserId(realNflxUserId);

    // Warp to the attestation's expiration so the 1-minute lookahead check passes
    // (contract requires expiration <= block.timestamp + 60)
    vm.warp(realExpiration);

    IGMTokenManager.Quote memory realQuote = IGMTokenManager.Quote({
      chainId: 1,
      attestationId: 12088645379121812514437369881650129103,
      userId: realNflxUserId,
      asset: NFLX_ON,
      price: realPrice,
      quantity: 10e18,
      expiration: realExpiration,
      side: 0, // BUY
      additionalData: bytes32(0)
    });

    // Real EIP-712 signature from Ondo's attestation signer (base64-decoded)
    bytes
      memory realSignature = hex"754132d4b63cd1c4084bb2ad2ac1e1ccf90b4e76c99dedb4441036fdc9414aaf5240b778aef005d2bef7ea728406dca0a24b32408f9fe8a9b0d97ea5816767921b";

    _updateSinglePrice(realQuote, realSignature);

    (uint256 price, uint256 updatedAt, uint256 expiration) = _callAttestedPrices(NFLX_ON);
    assertEq(price, realPrice);
    assertEq(updatedAt, block.timestamp);
    assertEq(expiration, realExpiration);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // updatePrices — happy path
  // ═══════════════════════════════════════════════════════════════════════

  function test_updatePrices_storesAttestedPrice() public {
    IGMTokenManager.Quote memory quote = _buildDefaultQuote();
    bytes memory sig = _signQuote(quote);

    _updateSinglePrice(quote, sig);

    (uint256 price, uint256 updatedAt, uint256 expiration) = _callAttestedPrices(NFLX_ON);
    assertEq(price, quote.price);
    assertEq(updatedAt, block.timestamp);
    assertEq(expiration, quote.expiration);
  }

  function test_updatePrices_emitsPriceUpdated() public {
    IGMTokenManager.Quote memory quote = _buildDefaultQuote();
    bytes memory sig = _signQuote(quote);

    // Expect event: PriceUpdated(address indexed gmToken, uint256 price, uint256 updatedAt)
    vm.expectEmit(true, false, false, true, attestationOracle);
    emit PriceUpdated(NFLX_ON, quote.price, block.timestamp);

    _updateSinglePrice(quote, sig);
  }

  // Event declaration for vm.expectEmit (matches the 0.8.28 contract's event)
  event PriceUpdated(address indexed gmToken, uint256 price, uint256 updatedAt);

  function test_updatePrices_multipleTokens() public {
    // Mock sanity oracle to revert for both tokens so the sanity check is skipped
    _mockSanityOracleRevert(NFLX_ON);
    _mockSanityOracleRevert(GOOGLON);

    IGMTokenManager.Quote memory quoteNflx = _buildQuoteForAsset(NFLX_ON, 1030e18, 1e18, block.timestamp);
    IGMTokenManager.Quote memory quoteGoogl = _buildQuoteForAsset(GOOGLON, 200e18, 2e18, block.timestamp);

    bytes memory sigNflx = _signQuote(quoteNflx);
    bytes memory sigGoogl = _signQuote(quoteGoogl);

    IGMTokenManager.Quote[] memory quotes = new IGMTokenManager.Quote[](2);
    quotes[0] = quoteNflx;
    quotes[1] = quoteGoogl;
    bytes[] memory sigs = new bytes[](2);
    sigs[0] = sigNflx;
    sigs[1] = sigGoogl;

    _callUpdatePrices(quotes, sigs);

    (uint256 priceNflx, , ) = _callAttestedPrices(NFLX_ON);
    assertEq(priceNflx, 1030e18);

    (uint256 priceGoogl, , ) = _callAttestedPrices(GOOGLON);
    assertEq(priceGoogl, 200e18);
  }

  function test_updatePrices_overwritesWithNewerExpiration() public {
    // First update
    IGMTokenManager.Quote memory quote1 = _buildDefaultQuote();
    _updateSinglePrice(quote1, _signQuote(quote1));

    // Warp forward so we can set a newer expiration
    vm.warp(block.timestamp + 10);

    // Second update with newer expiration and slightly different price
    IGMTokenManager.Quote memory quote2 = _buildQuote(1035e18, 1e18, block.timestamp);
    _updateSinglePrice(quote2, _signQuote(quote2));

    (uint256 price, , ) = _callAttestedPrices(NFLX_ON);
    assertEq(price, 1035e18);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // updatePrices — validation
  // ═══════════════════════════════════════════════════════════════════════

  function test_revert_updatePrices_arrayLengthMismatch() public {
    IGMTokenManager.Quote[] memory quotes = new IGMTokenManager.Quote[](1);
    quotes[0] = _buildDefaultQuote();
    bytes[] memory sigs = new bytes[](2);
    sigs[0] = _signQuote(quotes[0]);
    sigs[1] = _signQuote(quotes[0]);

    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("ArrayLengthMismatch()"))));
    _callUpdatePrices(quotes, sigs);
  }

  function test_revert_updatePrices_staleAttestation() public {
    // First update
    IGMTokenManager.Quote memory quote1 = _buildDefaultQuote();
    _updateSinglePrice(quote1, _signQuote(quote1));

    // Try to update with same expiration (not strictly greater)
    IGMTokenManager.Quote memory quote2 = _buildQuote(1035e18, 1e18, block.timestamp);
    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("StaleAttestation()"))));
    _updateSinglePrice(quote2, _signQuote(quote2));
  }

  function test_revert_updatePrices_invalidChainId() public {
    IGMTokenManager.Quote memory quote = _buildDefaultQuote();
    quote.chainId = 42161; // Arbitrum, not Ethereum
    bytes memory sig = _signQuote(quote);

    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("InvalidChainId()"))));
    _updateSinglePrice(quote, sig);
  }

  function test_revert_updatePrices_unauthorizedUserId() public {
    IGMTokenManager.Quote memory quote = _buildDefaultQuote();
    quote.userId = bytes32(uint256(0xDEAD));
    bytes memory sig = _signQuote(quote);

    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("UnauthorizedUserId()"))));
    _updateSinglePrice(quote, sig);
  }

  function test_revert_updatePrices_invalidQuoteSide() public {
    IGMTokenManager.Quote memory quote = _buildDefaultQuote();
    quote.side = uint8(IGMTokenManager.QuoteSide.SELL);
    bytes memory sig = _signQuote(quote);

    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("InvalidQuoteSide()"))));
    _updateSinglePrice(quote, sig);
  }

  function test_revert_updatePrices_quoteExpirationTooFar() public {
    IGMTokenManager.Quote memory quote = _buildDefaultQuote();
    quote.expiration = block.timestamp + 61; // > 1 minute
    bytes memory sig = _signQuote(quote);

    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("QuoteExpirationTooFar()"))));
    _updateSinglePrice(quote, sig);
  }

  function test_updatePrices_expirationAtEdge() public {
    IGMTokenManager.Quote memory quote = _buildDefaultQuote();
    quote.expiration = block.timestamp + 60; // Exactly 1 minute — should succeed
    bytes memory sig = _signQuote(quote);

    _updateSinglePrice(quote, sig);

    (uint256 price, , ) = _callAttestedPrices(NFLX_ON);
    assertEq(price, quote.price);
  }

  function test_revert_updatePrices_quoteExpirationTooOld() public {
    // Warp forward so expiration can be far in the past (block.timestamp underflow-safe)
    vm.warp(block.timestamp + 1000);

    IGMTokenManager.Quote memory quote = _buildDefaultQuote();
    quote.expiration = block.timestamp - 61; // > 1 minute in the past
    bytes memory sig = _signQuote(quote);

    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("StaleAttestation()"))));
    _updateSinglePrice(quote, sig);
  }

  function test_updatePrices_expirationAtPastEdge() public {
    // Warp forward so expiration can be in the past
    vm.warp(block.timestamp + 1000);

    IGMTokenManager.Quote memory quote = _buildDefaultQuote();
    quote.expiration = block.timestamp - 60; // Exactly 1 minute in the past — should succeed
    bytes memory sig = _signQuote(quote);

    _updateSinglePrice(quote, sig);

    (uint256 price, , ) = _callAttestedPrices(NFLX_ON);
    assertEq(price, quote.price);
  }

  function test_revert_updatePrices_firstSubmissionRejectsHistoricalQuote() public {
    // Regression test for NM-002: a stale but validly-signed historical quote
    // must be rejected on first submission for a newly-listed token, even though
    // the stored expiration is zero.
    vm.warp(block.timestamp + 10_000);

    // Attacker-replayed quote: signed long ago, expiration far in the past.
    IGMTokenManager.Quote memory quote = _buildDefaultQuote();
    quote.expiration = block.timestamp - 5_000;
    bytes memory sig = _signQuote(quote);

    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("StaleAttestation()"))));
    _updateSinglePrice(quote, sig);
  }

  function test_revert_updatePrices_quoteValueBelowMin() public {
    // price * quantity / 1e18 < MIN_QUOTE_VALUE (1e18)
    // Set price = 5e17, quantity = 1e18 => quoteValue = 5e17 < 1e18
    IGMTokenManager.Quote memory quote = _buildQuote(5e17, 1e18, block.timestamp);
    bytes memory sig = _signQuote(quote);

    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("QuoteValueOutOfRange()"))));
    _updateSinglePrice(quote, sig);
  }

  function test_revert_updatePrices_quoteValueAboveMax() public {
    // price * quantity / 1e18 > MAX_QUOTE_VALUE (1_000_000e18)
    // Set price = 1000e18, quantity = 1_000_001e18 => quoteValue > 1_000_000e18
    IGMTokenManager.Quote memory quote = _buildQuote(1000e18, 1_000_001e18, block.timestamp);
    bytes memory sig = _signQuote(quote);

    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("QuoteValueOutOfRange()"))));
    _updateSinglePrice(quote, sig);
  }

  function test_revert_updatePrices_invalidSignature() public {
    IGMTokenManager.Quote memory quote = _buildDefaultQuote();
    // Garbage signature (65 bytes of zeros)
    bytes memory garbageSig = new bytes(65);

    vm.expectRevert(); // ECDSA.recover will revert
    _updateSinglePrice(quote, garbageSig);
  }

  function test_revert_updatePrices_wrongSigner() public {
    IGMTokenManager.Quote memory quote = _buildDefaultQuote();
    // Sign with a different key whose address does NOT have the role
    uint256 wrongKey = 0xBEEF;
    bytes memory sig = _signQuoteWithKey(quote, wrongKey);

    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("InvalidAttestationSignature()"))));
    _updateSinglePrice(quote, sig);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // updatePrices — sanity check oracle
  // ═══════════════════════════════════════════════════════════════════════

  function test_revert_updatePrices_sanityDeviationTooLarge() public {
    // Mock sanity oracle with a price that deviates >10% from attestation
    // Attestation: 1030e18, Sanity: 1400e18 => deviation = 370/1030 = 35.9% > 10%
    _mockSanityOraclePrice(NFLX_ON, 1400e18, uint64(block.timestamp), 172800, 0);

    IGMTokenManager.Quote memory quote = _buildDefaultQuote();
    bytes memory sig = _signQuote(quote);

    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("SanityCheckDeviationTooLarge()"))));
    _updateSinglePrice(quote, sig);
  }

  function test_updatePrices_sanityCheckPasses_withinDeviation() public {
    // Mock sanity oracle with a price within 10% of attestation
    // Attestation: 1030e18, Sanity: 1060e18 => deviation = 30/1030 = 2.9% < 10%
    _mockSanityOraclePrice(NFLX_ON, 1060e18, uint64(block.timestamp), 172800, 0);

    IGMTokenManager.Quote memory quote = _buildDefaultQuote();
    bytes memory sig = _signQuote(quote);

    _updateSinglePrice(quote, sig);

    (uint256 price, , ) = _callAttestedPrices(NFLX_ON);
    assertEq(price, 1030e18);
  }

  function test_updatePrices_sanityCheckSkipped_oracleUnavailable() public {
    _mockSanityOracleRevert(NFLX_ON);

    IGMTokenManager.Quote memory quote = _buildDefaultQuote();
    bytes memory sig = _signQuote(quote);

    // Should succeed despite sanity oracle reverting
    _updateSinglePrice(quote, sig);

    (uint256 price, , ) = _callAttestedPrices(NFLX_ON);
    assertEq(price, 1030e18);
  }

  function test_updatePrices_sanityCheckSkipped_priceZero() public {
    // Sanity oracle returns price=0 — deviation check should be skipped
    _mockSanityOraclePrice(NFLX_ON, 0, uint64(block.timestamp), 172800, 0);

    IGMTokenManager.Quote memory quote = _buildDefaultQuote();
    bytes memory sig = _signQuote(quote);

    _updateSinglePrice(quote, sig);

    (uint256 price, , ) = _callAttestedPrices(NFLX_ON);
    assertEq(price, 1030e18);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // getPrice
  // ═══════════════════════════════════════════════════════════════════════

  function test_getPrice_returnsAttestedPrice() public {
    // Mock sanity oracle to revert so only attested price is available
    _mockSanityOracleRevert(NFLX_ON);

    _storeDefaultPrice();

    (uint256 price, uint256 updatedAt) = _callGetPrice(NFLX_ON);
    assertEq(price, 1030e18);
    assertEq(updatedAt, block.timestamp);
  }

  function test_getPrice_returnsSanityPrice_noAttestation() public {
    // No attested price stored; mock a valid sanity oracle price
    _mockSanityOraclePrice(NFLX_ON, 1050e18, uint64(block.timestamp), 172800, 0);

    (uint256 price, uint256 updatedAt) = _callGetPrice(NFLX_ON);
    assertEq(price, 1050e18);
    assertEq(updatedAt, block.timestamp);
  }

  function test_getPrice_returnsAttestedWhenFresher() public {
    // Sanity oracle was updated 100 seconds ago
    uint64 sanityTime = uint64(block.timestamp) - 100;
    _mockSanityOraclePrice(NFLX_ON, 1050e18, sanityTime, 172800, 0);

    // Attested price is updated now (block.timestamp)
    _storeDefaultPrice();

    (uint256 price, uint256 updatedAt) = _callGetPrice(NFLX_ON);
    assertEq(price, 1030e18, "should return attested price");
    assertEq(updatedAt, block.timestamp, "should return attested timestamp");
  }

  function test_getPrice_returnsSanityWhenFresher() public {
    // Store attested price first
    _storeDefaultPrice();

    // Warp forward so sanity oracle timestamp is newer
    vm.warp(block.timestamp + 200);
    _mockSanityOraclePrice(NFLX_ON, 1050e18, uint64(block.timestamp), 172800, 0);

    (uint256 price, uint256 updatedAt) = _callGetPrice(NFLX_ON);
    assertEq(price, 1050e18, "should return sanity price");
    assertEq(updatedAt, block.timestamp, "should return sanity timestamp");
  }

  function test_getPrice_attestedStale_returnsSanity() public {
    // Store attested price
    _storeDefaultPrice();

    // Warp beyond maxProofAge (3600s)
    vm.warp(block.timestamp + MAX_PROOF_AGE + 1);

    // Mock fresh sanity oracle
    _mockSanityOraclePrice(NFLX_ON, 1050e18, uint64(block.timestamp), 172800, 0);

    (uint256 price, ) = _callGetPrice(NFLX_ON);
    assertEq(price, 1050e18, "should return sanity price after attested expires");
  }

  function test_getPrice_sanityStale_returnsAttested() public {
    // Mock stale sanity oracle (lastUpdated + maxTimeDelay < block.timestamp)
    uint64 staleTime = uint64(block.timestamp) - 200000; // Well beyond any maxTimeDelay
    _mockSanityOraclePrice(NFLX_ON, 1050e18, staleTime, 172800, 0);

    // Store fresh attested price
    _storeDefaultPrice();

    (uint256 price, ) = _callGetPrice(NFLX_ON);
    assertEq(price, 1030e18, "should return attested price when sanity is stale");
  }

  function test_revert_getPrice_noPriceAvailable() public {
    // No attested price, sanity oracle reverts
    _mockSanityOracleRevert(NFLX_ON);

    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("NoPriceAvailable()"))));
    _callGetPrice(NFLX_ON);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Owner functions — setGmTokenManager
  // ═══════════════════════════════════════════════════════════════════════

  function test_setGmTokenManager_updatesValue() public {
    address newManager = makeAddr("newManager");
    vm.prank(owner);
    _callSetGmTokenManager(newManager);

    assertEq(address(IOndoAttestationOracle(attestationOracle).gmTokenManager()), newManager);
  }

  event GmTokenManagerUpdated(address gmTokenManager);

  function test_setGmTokenManager_emitsEvent() public {
    address newManager = makeAddr("newManager");
    vm.expectEmit(false, false, false, true, attestationOracle);
    emit GmTokenManagerUpdated(newManager);

    vm.prank(owner);
    _callSetGmTokenManager(newManager);
  }

  function test_revert_setGmTokenManager_notOwner() public {
    vm.prank(makeAddr("stranger"));
    vm.expectRevert(); // OwnableUnauthorizedAccount
    _callSetGmTokenManager(makeAddr("newManager"));
  }

  function test_revert_setGmTokenManager_zeroAddress() public {
    vm.prank(owner);
    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("ZeroAddress(string)")), "_gmTokenManager"));
    _callSetGmTokenManager(address(0));
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Owner functions — setAllowedUserId
  // ═══════════════════════════════════════════════════════════════════════

  function test_setAllowedUserId_updatesValue() public {
    bytes32 newId = bytes32(uint256(0x1234));
    vm.prank(owner);
    _callSetAllowedUserId(newId);

    (bool ok, bytes memory data) = attestationOracle.staticcall(abi.encodeWithSignature("allowedUserId()"));
    require(ok);
    assertEq(abi.decode(data, (bytes32)), newId);
  }

  function test_revert_setAllowedUserId_notOwner() public {
    vm.prank(makeAddr("stranger"));
    vm.expectRevert();
    _callSetAllowedUserId(bytes32(uint256(0x1234)));
  }

  function test_setAllowedUserId_zeroDisablesValidation() public {
    // Set allowedUserId to zero
    vm.prank(owner);
    _callSetAllowedUserId(bytes32(0));

    (bool ok, bytes memory data) = attestationOracle.staticcall(abi.encodeWithSignature("allowedUserId()"));
    require(ok);
    assertEq(abi.decode(data, (bytes32)), bytes32(0));

    // Build a quote with an arbitrary userId — should succeed because validation is disabled
    IGMTokenManager.Quote memory quote = _buildDefaultQuote();
    quote.userId = bytes32(uint256(0xDEAD));
    bytes memory sig = _signQuote(quote);

    _updateSinglePrice(quote, sig);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Owner functions — setProofConfig
  // ═══════════════════════════════════════════════════════════════════════

  function test_setProofConfig_updatesValue() public {
    vm.prank(owner);
    _callSetProofConfig(7200, 500, 2e18, 500_000e18);

    (bool ok, bytes memory data) = attestationOracle.staticcall(abi.encodeWithSignature("proofConfig()"));
    require(ok);
    (uint256 maxProofAge, uint256 sanityDeviationBps, uint256 minQuoteValue, uint256 maxQuoteValue) = abi.decode(
      data,
      (uint256, uint256, uint256, uint256)
    );
    assertEq(maxProofAge, 7200);
    assertEq(sanityDeviationBps, 500);
    assertEq(minQuoteValue, 2e18);
    assertEq(maxQuoteValue, 500_000e18);
  }

  function test_revert_setProofConfig_notOwner() public {
    vm.prank(makeAddr("stranger"));
    vm.expectRevert();
    _callSetProofConfig(7200, 500, 2e18, 500_000e18);
  }

  function test_revert_setProofConfig_zeroMinQuoteValue() public {
    vm.prank(owner);
    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("ZeroValue(string)")), "_config.minQuoteValue"));
    _callSetProofConfig(7200, 500, 0, 500_000e18);
  }

  function test_revert_setProofConfig_zeroMaxProofAge() public {
    vm.prank(owner);
    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("ZeroValue(string)")), "_config.maxProofAge"));
    _callSetProofConfig(0, 500, 2e18, 500_000e18);
  }

  function test_revert_setProofConfig_maxQuoteValueBelowMin() public {
    vm.prank(owner);
    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("InvalidProofConfig(string)")), "maxQuoteValue"));
    _callSetProofConfig(7200, 500, 2e18, 2e18 - 1);
  }

  function test_revert_setProofConfig_zeroSanityDeviationBps() public {
    vm.prank(owner);
    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("InvalidProofConfig(string)")), "sanityDeviationBps"));
    _callSetProofConfig(7200, 0, 2e18, 500_000e18);
  }

  function test_revert_setProofConfig_sanityDeviationBpsAboveDenominator() public {
    vm.prank(owner);
    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("InvalidProofConfig(string)")), "sanityDeviationBps"));
    _callSetProofConfig(7200, 10_001, 2e18, 500_000e18);
  }
}
