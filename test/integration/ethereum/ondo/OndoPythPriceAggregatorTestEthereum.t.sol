// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {OndoPythPriceAggregatorTestSetup} from "test/integration/common/ondo/OndoPythPriceAggregatorTestSetup.t.sol";
import {EthereumSetup} from "test/integration/utils/foundry/chains/EthereumSetup.t.sol";

contract OndoPythPriceAggregatorTestEthereum is OndoPythPriceAggregatorTestSetup, EthereumSetup {
  constructor() EthereumSetup(24820854) OndoPythPriceAggregatorTestSetup() {}

  function setUp() public override(OndoPythPriceAggregatorTestSetup, EthereumSetup) {
    EthereumSetup.setUp();
    OndoPythPriceAggregatorTestSetup.setUp();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Constructor
  // ═══════════════════════════════════════════════════════════════════════

  function test_constructor_setsImmutables() public view {
    (bool s2, bytes memory d2) = aggregator.staticcall(abi.encodeWithSignature("pythOracleContract()"));
    require(s2);
    assertEq(abi.decode(d2, (address)), PYTH_CONTRACT);

    (bool s3, bytes memory d3) = aggregator.staticcall(abi.encodeWithSignature("gmTokenManager()"));
    require(s3);
    assertEq(abi.decode(d3, (address)), GM_TOKEN_MANAGER);

    (bool s4, bytes memory d4) = aggregator.staticcall(abi.encodeWithSignature("sValueOracle()"));
    require(s4);
    assertEq(abi.decode(d4, (address)), SVALUE_ORACLE);

    (bool s5, bytes memory d5) = aggregator.staticcall(abi.encodeWithSignature("ondoAsset()"));
    require(s5);
    assertEq(abi.decode(d5, (address)), NVDA_ON);

    (bool s6, bytes memory d6) = aggregator.staticcall(abi.encodeWithSignature("onchainMaxAge()"));
    require(s6);
    assertEq(uint256(abi.decode(d6, (uint32))), uint256(ONCHAIN_MAX_AGE));

    (bool s7, bytes memory d7) = aggregator.staticcall(abi.encodeWithSignature("pythMaxAge()"));
    require(s7);
    assertEq(uint256(abi.decode(d7, (uint32))), uint256(PYTH_MAX_AGE));

    (bool s8, bytes memory d8) = aggregator.staticcall(abi.encodeWithSignature("pythMinConfidenceRatio()"));
    require(s8);
    assertEq(uint256(abi.decode(d8, (uint32))), uint256(PYTH_MIN_CONFIDENCE_RATIO));
  }

  function test_revert_constructor_zeroPythOracle() public {
    bytes32[] memory priceIds = new bytes32[](1);
    priceIds[0] = NVDA;
    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("ZeroAddress(string)")), "_pythOracleContract"));
    deployCode(
      "OndoPythPriceAggregator.sol:OndoPythPriceAggregator",
      abi.encode(
        address(0),
        GM_TOKEN_MANAGER,
        SVALUE_ORACLE,
        NVDA_ON,
        priceIds,
        ONCHAIN_MAX_AGE,
        PYTH_MAX_AGE,
        PYTH_MIN_CONFIDENCE_RATIO
      )
    );
  }

  function test_revert_constructor_zeroGMTokenManager() public {
    bytes32[] memory priceIds = new bytes32[](1);
    priceIds[0] = NVDA;
    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("ZeroAddress(string)")), "_gmTokenManager"));
    deployCode(
      "OndoPythPriceAggregator.sol:OndoPythPriceAggregator",
      abi.encode(
        PYTH_CONTRACT,
        address(0),
        SVALUE_ORACLE,
        NVDA_ON,
        priceIds,
        ONCHAIN_MAX_AGE,
        PYTH_MAX_AGE,
        PYTH_MIN_CONFIDENCE_RATIO
      )
    );
  }

  function test_revert_constructor_emptyPythPriceIds() public {
    bytes32[] memory priceIds = new bytes32[](0);
    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("NoPythPriceIds()"))));
    deployCode(
      "OndoPythPriceAggregator.sol:OndoPythPriceAggregator",
      abi.encode(
        PYTH_CONTRACT,
        GM_TOKEN_MANAGER,
        SVALUE_ORACLE,
        NVDA_ON,
        priceIds,
        ONCHAIN_MAX_AGE,
        PYTH_MAX_AGE,
        PYTH_MIN_CONFIDENCE_RATIO
      )
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // decimals
  // ═══════════════════════════════════════════════════════════════════════

  function test_decimals_returns8() public view {
    assertEq(uint256(_getDecimals()), uint256(8));
  }

  // ═══════════════════════════════════════════════════════════════════════
  // latestRoundData — real end-to-end (Pyth + Ondo oracles)
  // ═══════════════════════════════════════════════════════════════════════

  function test_latestRoundData_returnsValidPrice() public view {
    (, int256 answer, , uint256 updatedAt, ) = _getLatestRoundData();

    assertGt(answer, 0, "price should be positive");
    assertGt(updatedAt, 0, "updatedAt should be non-zero");

    // NVDA price should be reasonable: between $10 and $10,000 (in 8 decimals)
    assertGt(answer, int256(10e8), "NVDA price too low");
    assertLt(answer, int256(10_000e8), "NVDA price too high");
  }

  function test_latestRoundData_priceMatchesPreMarketFeed() public view {
    (, int256 answer, , uint256 updatedAt, ) = _getLatestRoundData();

    // Convert aggregator answer (8 dec) back to 18 dec for comparison
    uint256 aggregatorPrice18Dec = uint256(answer) * 1e10;

    // Default sValue = 1e18 (no-op multiplier), so the answer matches raw Pyth price
    assertApproxEqRel(aggregatorPrice18Dec, NVDA_PRE_MARKET_PRICE_18DEC, 0.01e18);
    assertEq(updatedAt, NVDA_PRE_MARKET_PUBLISH_TIME);
  }

  function test_latestRoundData_converts18DecTo8Dec() public view {
    (, int256 answer, , , ) = _getLatestRoundData();

    uint256 backTo18 = uint256(answer) * 1e10;
    assertApproxEqRel(backTo18, NVDA_PRE_MARKET_PRICE_18DEC, 0.01e18);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // latestRoundData — onchain vs offchain selection
  // ═══════════════════════════════════════════════════════════════════════

  function test_latestRoundData_returnsOnchainPrice_whenFresher() public {
    uint64 onchainTime = uint64(NVDA_PRE_MARKET_PUBLISH_TIME + 60);
    _mockOnchainPrice(NVDA_PRE_MARKET_PRICE_18DEC, onchainTime, 1000);

    vm.warp(uint256(onchainTime));

    (, , , uint256 updatedAt, ) = _getLatestRoundData();

    assertEq(updatedAt, uint256(onchainTime));
  }

  function test_latestRoundData_fallsBackToOnchain_whenAllPythFeedsInvalid() public {
    _mockAllPythFeedsRevert();

    (, int256 answer, , uint256 updatedAt, ) = _getLatestRoundData();

    // Falls back to onchain price with the sanity oracle's own lastUpdated timestamp
    assertGt(answer, 0, "onchain fallback price should be positive");
    assertLt(updatedAt, block.timestamp, "onchain timestamp should be older than current time");
  }

  // ═══════════════════════════════════════════════════════════════════════
  // latestRoundData — deviation check
  // ═══════════════════════════════════════════════════════════════════════

  function test_revert_latestRoundData_priceDeviationTooLarge() public {
    // Mock onchain price 20% higher, with tight 5% tolerance
    uint256 inflatedPrice = (NVDA_PRE_MARKET_PRICE_18DEC * 120) / 100;
    _mockOnchainPrice(inflatedPrice, uint64(block.timestamp), 500);

    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("PriceDeviationTooLarge()"))));
    _getLatestRoundData();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // _getOnchainPrice path
  // ═══════════════════════════════════════════════════════════════════════

  function test_revert_latestRoundData_onchainPriceZero() public {
    _mockOnchainPrice(0, uint64(block.timestamp), 500);

    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("OnchainOraclePriceInvalid()"))));
    _getLatestRoundData();
  }

  function test_revert_latestRoundData_onchainPriceStale() public {
    uint64 staleTimestamp = uint64(block.timestamp) - uint64(ONCHAIN_MAX_AGE) - 1;
    _mockOnchainPrice(NVDA_PRE_MARKET_PRICE_18DEC, staleTimestamp, 500);

    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("OnchainOraclePriceStale()"))));
    _getLatestRoundData();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // _getFreshestOffchainPrice path
  // ═══════════════════════════════════════════════════════════════════════

  function test_latestRoundData_skipsFeedWithLowConfidence() public {
    // Override a feed with low confidence (price/conf < 50)
    _mockPythPrice(NVDA, int64(11_000_000_000), uint64(300_000_000), int32(-8), block.timestamp + 30);

    (, int256 answer, , , ) = _getLatestRoundData();

    assertGt(answer, 0, "should still return valid price from other feeds");
  }

  function test_latestRoundData_skipsFeedWithInvalidExponent() public {
    _mockPythPrice(NVDA, int64(11_000_000_000), uint64(10_000_000), int32(0), block.timestamp + 30);
    _mockPythPrice(NVDA_OVERNIGHT, int64(11_000_000_000), uint64(10_000_000), int32(-19), block.timestamp + 20);

    (, int256 answer, , , ) = _getLatestRoundData();

    assertGt(answer, 0, "should still return valid price from remaining feeds");
  }

  function test_latestRoundData_handlesRevertingPythFeed() public {
    // Make 3 feeds revert, leave NVDA_PRE_MARKET with real data
    _mockPythPriceRevert(NVDA);
    _mockPythPriceRevert(NVDA_OVERNIGHT);
    _mockPythPriceRevert(NVDA_POST_MARKET);

    (, int256 answer, , , ) = _getLatestRoundData();

    assertGt(answer, 0, "should return price from remaining valid feed");
  }

  // ═══════════════════════════════════════════════════════════════════════
  // _applySValue path
  // ═══════════════════════════════════════════════════════════════════════

  function test_latestRoundData_appliesSValueCorrectly() public {
    // sValue = 1.5 -> price should be 1.5x the raw Pyth price
    _mockSValue(uint128(1.5e18), false);

    // Onchain must also reflect sValue-adjusted price to pass deviation check
    uint256 adjustedOnchainPrice = (NVDA_PRE_MARKET_PRICE_18DEC * 150) / 100;
    _mockOnchainPrice(adjustedOnchainPrice, uint64(block.timestamp), 500);

    (, int256 answer, , , ) = _getLatestRoundData();

    int256 expectedAnswer = int256((NVDA_PRE_MARKET_PRICE_18DEC * 150) / 100 / 1e10);
    assertApproxEqRel(uint256(answer), uint256(expectedAnswer), 0.01e18);
  }

  function test_revert_latestRoundData_ondoMintingPaused() public {
    _mockMintingPaused(true);

    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("OndoMintingPaused()"))));
    _getLatestRoundData();
  }

  function test_revert_latestRoundData_ondoRedemptionsPaused() public {
    _mockRedemptionsPaused(true);

    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("OndoRedemptionsPaused()"))));
    _getLatestRoundData();
  }

  function test_revert_latestRoundData_ondoAssetPaused() public {
    _mockSValue(uint128(1e18), true);

    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("OndoAssetPaused()"))));
    _getLatestRoundData();
  }

  function test_revert_latestRoundData_sValueOracleReverts() public {
    // If the sValue oracle call itself reverts, the aggregator must revert rather than
    // silently treating the multiplier as 1e18.
    _mockSValueRevert();

    vm.expectRevert(abi.encodePacked("AssetNotFound"));
    _getLatestRoundData();
  }

  function test_revert_latestRoundData_sValueZero() public {
    // A zero sValue is indistinguishable from "no multiplier configured" and must revert.
    _mockSValue(uint128(0), false);

    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("InvalidSValue()"))));
    _getLatestRoundData();
  }
}
