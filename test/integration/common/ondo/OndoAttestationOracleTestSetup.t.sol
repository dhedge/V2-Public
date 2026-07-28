// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/TransparentUpgradeableProxy.sol";

import {IGMTokenManager} from "contracts/interfaces/ondo/IGMTokenManager.sol";
import {IOndoAttestationOracle} from "contracts/interfaces/ondo/IOndoAttestationOracle.sol";
import {BackboneSetup} from "test/integration/utils/foundry/BackboneSetup.t.sol";

abstract contract OndoAttestationOracleTestSetup is BackboneSetup {
  // --- Real mainnet contracts ---
  address public constant GM_TOKEN_MANAGER = 0x2c158BC456e027b2AfFCCadF1BDBD9f5fC4c5C8c;
  address public constant NFLX_ON = 0x032deC3372F25C41EA8054B4987a7c4832CDB338;

  // --- Test attestation signer ---
  uint256 internal constant SIGNER_PRIVATE_KEY = 0xA11CE;

  // --- Proof config ---
  uint256 internal constant MAX_PROOF_AGE = 3600; // 1 hour
  uint256 internal constant SANITY_DEVIATION_BPS = 1000; // 10%
  uint256 internal constant MIN_QUOTE_VALUE = 1e18;
  uint256 internal constant MAX_QUOTE_VALUE = 1_000_000e18;

  // --- EIP-712 ---
  bytes32 internal constant ONDO_USER_ID = 0x474d0000000000000e88de2c9ee3cae100000000000000000000000000000000;
  bytes32 internal constant QUOTE_TYPEHASH =
    keccak256(
      "Quote(uint256 chainId,uint256 attestationId,bytes32 userId,address asset,uint256 price,uint256 quantity,uint256 expiration,uint8 side,bytes32 additionalData)"
    );

  // --- Deployed oracle proxy ---
  address public attestationOracle;

  // --- Derived at setUp ---
  address internal signerAddress;
  bytes32 internal domainSeparator;
  bytes32 internal attestationSignerRole;

  // --- Selectors (computed from full ABI signatures) ---
  bytes4 internal constant INITIALIZE_SELECTOR =
    bytes4(keccak256("initialize(address,address,bytes32,(uint256,uint256,uint256,uint256))"));
  bytes4 internal constant UPDATE_PRICES_SELECTOR =
    bytes4(
      keccak256("updatePrices((uint256,uint256,bytes32,address,uint256,uint256,uint256,uint8,bytes32)[],bytes[])")
    );
  bytes4 internal constant SET_GM_TOKEN_MANAGER_SELECTOR = bytes4(keccak256("setGmTokenManager(address)"));
  bytes4 internal constant SET_ALLOWED_USER_ID_SELECTOR = bytes4(keccak256("setAllowedUserId(bytes32)"));
  bytes4 internal constant SET_PROOF_CONFIG_SELECTOR =
    bytes4(keccak256("setProofConfig((uint256,uint256,uint256,uint256))"));

  function setUp() public virtual override {
    super.setUp();

    // Read domain separator and attestation signer role from the real GMTokenManager
    domainSeparator = IGMTokenManager(GM_TOKEN_MANAGER).getDomainSeparator();
    attestationSignerRole = IGMTokenManager(GM_TOKEN_MANAGER).ATTESTATION_SIGNER_ROLE();

    // Derive test signer
    signerAddress = vm.addr(SIGNER_PRIVATE_KEY);

    // Mock the attestation signer role check so our test signer is accepted
    vm.mockCall(
      GM_TOKEN_MANAGER,
      abi.encodeWithSignature("hasRole(bytes32,address)", attestationSignerRole, signerAddress),
      abi.encode(true)
    );

    // Deploy OndoAttestationOracle implementation (0.8.28, cross-version)
    address impl = deployCode("OndoAttestationOracle.sol:OndoAttestationOracle");

    // Deploy OZ v3 TransparentUpgradeableProxy
    attestationOracle = address(new TransparentUpgradeableProxy(impl, proxyAdmin, ""));

    // Initialize the oracle via the proxy
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
    require(ok, "OndoAttestationOracle.initialize failed");

    vm.stopPrank(); // BackboneSetup.setUp() starts prank as owner
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Quote building helpers
  // ═══════════════════════════════════════════════════════════════════════

  function _buildQuote(
    uint256 _price,
    uint256 _quantity,
    uint256 _expiration
  ) internal pure returns (IGMTokenManager.Quote memory) {
    return _buildQuoteForAsset(NFLX_ON, _price, _quantity, _expiration);
  }

  function _buildQuoteForAsset(
    address _asset,
    uint256 _price,
    uint256 _quantity,
    uint256 _expiration
  ) internal pure returns (IGMTokenManager.Quote memory) {
    return
      IGMTokenManager.Quote({
        chainId: 1,
        attestationId: 123456789,
        userId: ONDO_USER_ID,
        asset: _asset,
        price: _price,
        quantity: _quantity,
        expiration: _expiration,
        side: uint8(IGMTokenManager.QuoteSide.BUY),
        additionalData: bytes32(0)
      });
  }

  /// @notice Build a default valid quote with price ~$1030 (close to real NFLX sanity oracle price at fork block)
  function _buildDefaultQuote() internal view returns (IGMTokenManager.Quote memory) {
    return _buildQuote(1030e18, 1e18, block.timestamp);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // EIP-712 signing
  // ═══════════════════════════════════════════════════════════════════════

  function _signQuote(IGMTokenManager.Quote memory _quote) internal view returns (bytes memory) {
    return _signQuoteWithKey(_quote, SIGNER_PRIVATE_KEY);
  }

  function _signQuoteWithKey(
    IGMTokenManager.Quote memory _quote,
    uint256 _privateKey
  ) internal view returns (bytes memory) {
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

    bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

    (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, digest);
    return abi.encodePacked(r, s, v);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Low-level call helpers (cross-version: 0.7.6 -> 0.8.28)
  // ═══════════════════════════════════════════════════════════════════════

  function _callUpdatePrices(IGMTokenManager.Quote[] memory _quotes, bytes[] memory _signatures) internal {
    (bool ok, bytes memory ret) = attestationOracle.call(
      abi.encodePacked(UPDATE_PRICES_SELECTOR, abi.encode(_quotes, _signatures))
    );
    if (!ok) {
      // Bubble up the revert
      assembly {
        revert(add(ret, 0x20), mload(ret))
      }
    }
  }

  function _updateSinglePrice(IGMTokenManager.Quote memory _quote, bytes memory _signature) internal {
    IGMTokenManager.Quote[] memory quotes = new IGMTokenManager.Quote[](1);
    quotes[0] = _quote;
    bytes[] memory sigs = new bytes[](1);
    sigs[0] = _signature;
    _callUpdatePrices(quotes, sigs);
  }

  /// @notice Convenience: build, sign, and store a default price for NFLX_ON
  function _storeDefaultPrice() internal {
    IGMTokenManager.Quote memory quote = _buildDefaultQuote();
    bytes memory sig = _signQuote(quote);
    _updateSinglePrice(quote, sig);
  }

  function _callGetPrice(address _token) internal view returns (uint256 price, uint256 updatedAt) {
    return IOndoAttestationOracle(attestationOracle).getPrice(_token);
  }

  function _callAttestedPrices(
    address _token
  ) internal view returns (uint256 price, uint256 updatedAt, uint256 expiration) {
    return IOndoAttestationOracle(attestationOracle).attestedPrices(_token);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Owner function call helpers
  // ═══════════════════════════════════════════════════════════════════════

  function _callSetGmTokenManager(address _gmTokenManager) internal {
    (bool ok, bytes memory ret) = attestationOracle.call(
      abi.encodeWithSelector(SET_GM_TOKEN_MANAGER_SELECTOR, _gmTokenManager)
    );
    if (!ok) {
      assembly {
        revert(add(ret, 0x20), mload(ret))
      }
    }
  }

  function _callSetAllowedUserId(bytes32 _userId) internal {
    (bool ok, bytes memory ret) = attestationOracle.call(abi.encodeWithSelector(SET_ALLOWED_USER_ID_SELECTOR, _userId));
    if (!ok) {
      assembly {
        revert(add(ret, 0x20), mload(ret))
      }
    }
  }

  function _callSetProofConfig(
    uint256 _maxProofAge,
    uint256 _sanityDeviationBps,
    uint256 _minQuoteValue,
    uint256 _maxQuoteValue
  ) internal {
    (bool ok, bytes memory ret) = attestationOracle.call(
      abi.encodePacked(
        SET_PROOF_CONFIG_SELECTOR,
        abi.encode(_maxProofAge, _sanityDeviationBps, _minQuoteValue, _maxQuoteValue)
      )
    );
    if (!ok) {
      assembly {
        revert(add(ret, 0x20), mload(ret))
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Mock helpers
  // ═══════════════════════════════════════════════════════════════════════

  function _getSanityCheckOracle() internal returns (address) {
    (bool ok, bytes memory data) = GM_TOKEN_MANAGER.call(abi.encodeWithSignature("sanityCheckOracle()"));
    require(ok, "sanityCheckOracle() failed");
    return abi.decode(data, (address));
  }

  function _mockSanityOraclePrice(
    address _asset,
    uint256 _price,
    uint64 _lastUpdated,
    uint32 _maxTimeDelay,
    uint16 _deviationBps
  ) internal {
    address sanityOracle = _getSanityCheckOracle();
    vm.mockCall(
      sanityOracle,
      abi.encodeWithSignature("prices(address)", _asset),
      abi.encode(_price, _lastUpdated, _maxTimeDelay, _deviationBps)
    );
  }

  function _mockSanityOracleRevert(address _asset) internal {
    address sanityOracle = _getSanityCheckOracle();
    vm.mockCallRevert(
      sanityOracle,
      abi.encodeWithSignature("prices(address)", _asset),
      abi.encodePacked("not available")
    );
  }

  function _mockMintingPaused(address _asset, bool _paused) internal {
    vm.mockCall(
      GM_TOKEN_MANAGER,
      abi.encodeWithSignature("gmTokenMintingPaused(address)", _asset),
      abi.encode(_paused)
    );
  }

  function _mockRedemptionsPaused(address _asset, bool _paused) internal {
    vm.mockCall(
      GM_TOKEN_MANAGER,
      abi.encodeWithSignature("gmTokenRedemptionsPaused(address)", _asset),
      abi.encode(_paused)
    );
  }
}
