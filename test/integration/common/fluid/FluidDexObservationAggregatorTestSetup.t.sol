// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {FluidDexObservationAggregator} from "contracts/priceAggregators/FluidDexObservationAggregator.sol";
import {IAggregatorV3Interface} from "contracts/interfaces/IAggregatorV3Interface.sol";
import {IFluidDexT1} from "contracts/interfaces/fluid/IFluidDexT1.sol";

/// @notice Chain-agnostic test setup for FluidDexObservationAggregator
/// @dev This aggregator records price observations externally (via automation) and stores them in its own storage.
///      Unlike FluidDexTWAPAggregator, it does NOT require Fluid DEX oracle activation.
abstract contract FluidDexObservationAggregatorTestSetup is Test {
  // Constructor parameters
  IFluidDexT1 public immutable pool;
  address public immutable mainToken;
  IAggregatorV3Interface public immutable pairTokenUsdAggregator;
  uint256 public immutable twapPeriod;
  uint256 public immutable minObservationInterval;
  uint256 public immutable maxStaleness;
  uint256 public immutable volatilityLimit;
  uint256 public immutable bufferSize;

  // Reference oracle for price comparison
  IAggregatorV3Interface public immutable referenceOracle;
  uint256 public immutable maxDeviation;

  // Contract under test
  FluidDexObservationAggregator public aggregator;

  // Test accounts
  address public owner;
  address public user;
  address public keeper;

  constructor(
    IFluidDexT1 _pool,
    address _mainToken,
    IAggregatorV3Interface _pairTokenUsdAggregator,
    uint256 _twapPeriod,
    uint256 _minObservationInterval,
    uint256 _maxStaleness,
    uint256 _volatilityLimit,
    uint256 _bufferSize,
    IAggregatorV3Interface _referenceOracle,
    uint256 _maxDeviation
  ) {
    pool = _pool;
    mainToken = _mainToken;
    pairTokenUsdAggregator = _pairTokenUsdAggregator;
    twapPeriod = _twapPeriod;
    minObservationInterval = _minObservationInterval;
    maxStaleness = _maxStaleness;
    volatilityLimit = _volatilityLimit;
    bufferSize = _bufferSize;
    referenceOracle = _referenceOracle;
    maxDeviation = _maxDeviation;
  }

  function setUp() public virtual {
    owner = makeAddr("owner");
    user = makeAddr("user");
    keeper = makeAddr("keeper");

    // Deploy the FluidDexObservationAggregator
    aggregator = new FluidDexObservationAggregator(
      owner,
      pool,
      mainToken,
      pairTokenUsdAggregator,
      twapPeriod,
      minObservationInterval,
      maxStaleness,
      volatilityLimit,
      bufferSize
    );

    // Authorize keeper for tests
    vm.prank(owner);
    aggregator.setKeeperAuthorization(keeper, true);
  }

  /* ========== DEPLOYMENT TESTS ========== */

  function test_decimals_returns_8() public view {
    assertEq(aggregator.decimals(), 8, "Decimals should be 8");
  }

  function test_immutables_are_set_correctly() public view {
    assertEq(address(aggregator.pool()), address(pool), "Pool should match");
    assertEq(aggregator.mainToken(), mainToken, "MainToken should match");
    assertEq(
      address(aggregator.pairTokenUsdAggregator()),
      address(pairTokenUsdAggregator),
      "PairTokenUsdAggregator should match"
    );
    assertEq(aggregator.bufferSize(), bufferSize, "BufferSize should match");

    // Verify token0/token1 identification and pairToken derivation
    IFluidDexT1.ConstantViews memory constants = pool.constantsView();
    address token0 = constants.token0;
    address token1 = constants.token1;

    if (aggregator.mainTokenIsToken0()) {
      assertEq(aggregator.mainToken(), token0, "If mainTokenIsToken0, mainToken should be token0");
      assertEq(aggregator.pairToken(), token1, "If mainTokenIsToken0, pairToken should be token1");
    } else {
      assertEq(aggregator.mainToken(), token1, "If not mainTokenIsToken0, mainToken should be token1");
      assertEq(aggregator.pairToken(), token0, "If not mainTokenIsToken0, pairToken should be token0");
    }
  }

  function test_storage_variables_are_set_correctly() public view {
    assertEq(aggregator.twapPeriod(), twapPeriod, "TwapPeriod should match");
    assertEq(aggregator.minObservationInterval(), minObservationInterval, "MinObservationInterval should match");
    assertEq(aggregator.maxStaleness(), maxStaleness, "MaxStaleness should match");
    assertEq(aggregator.volatilityLimit(), volatilityLimit, "VolatilityLimit should match");
  }

  function test_initial_state_is_empty() public view {
    assertEq(aggregator.totalObservations(), 0, "Total observations should be 0");
    assertEq(aggregator.nextObservationIndex(), 0, "Next observation index should be 0");
  }

  function test_owner_is_set_correctly() public view {
    assertEq(aggregator.owner(), owner, "Owner should be set correctly");
  }

  /* ========== RECORD OBSERVATION TESTS ========== */

  function test_recordObservation_succeeds_first_time() public {
    vm.prank(keeper);
    aggregator.recordObservation();

    assertEq(aggregator.totalObservations(), 1, "Should have 1 observation");
    assertEq(aggregator.nextObservationIndex(), 1, "Next index should be 1");
  }

  function test_recordObservation_respects_minObservationInterval() public {
    vm.prank(keeper);
    aggregator.recordObservation();

    // Try to record again immediately - should revert
    vm.expectRevert(
      abi.encodeWithSelector(FluidDexObservationAggregator.ObservationTooSoon.selector, 0, minObservationInterval)
    );
    vm.prank(keeper);
    aggregator.recordObservation();

    // Warp past the interval
    vm.warp(block.timestamp + minObservationInterval);

    // Should succeed now
    vm.prank(keeper);
    aggregator.recordObservation();
    assertEq(aggregator.totalObservations(), 2, "Should have 2 observations");
  }

  function test_recordObservation_emits_event() public {
    vm.prank(keeper);
    aggregator.recordObservation();

    // Get the stored price to verify it matches the emitted value
    (, uint192 storedPrice) = aggregator.observations(0);

    // Now test the event emission with the actual value
    vm.warp(block.timestamp + minObservationInterval);

    vm.expectEmit(true, true, true, true);
    emit FluidDexObservationAggregator.ObservationRecorded(storedPrice);
    vm.prank(keeper);
    aggregator.recordObservation();
  }

  function test_recordObservation_stores_correct_timestamp() public {
    uint256 expectedTimestamp = block.timestamp;
    vm.prank(keeper);
    aggregator.recordObservation();

    (uint64 timestamp, ) = aggregator.observations(0);
    assertEq(timestamp, expectedTimestamp, "Timestamp should match block.timestamp");
  }

  function test_recordObservation_stores_positive_price() public {
    vm.prank(keeper);
    aggregator.recordObservation();

    (, uint192 price) = aggregator.observations(0);
    assertGt(price, 0, "Price should be positive");
  }

  /* ========== VOLATILITY LIMIT TESTS ========== */

  function test_recordObservation_reverts_on_high_volatility_price_increase() public {
    _testVolatilityRevert(11000, 999); // 10% higher, expect ~999 bps
  }

  function test_recordObservation_reverts_on_high_volatility_price_decrease() public {
    _testVolatilityRevert(9000, 1000); // 10% lower, expect ~1000 bps
  }

  function test_recordObservation_reverts_on_unexpected_success() public {
    // Mock the pool to return success instead of reverting
    vm.mockCall(
      address(pool),
      abi.encodeWithSelector(IFluidDexT1.getPricesAndExchangePrices.selector),
      abi.encode(uint256(0)) // Return some data instead of reverting
    );

    vm.expectRevert(FluidDexObservationAggregator.UnexpectedSuccess.selector);
    vm.prank(keeper);
    aggregator.recordObservation();
  }

  function test_recordObservation_reverts_on_revert_data_too_short() public {
    // Mock the pool to revert with too-short data (4 bytes = just selector)
    bytes memory shortRevertData = hex"12345678";

    vm.mockCallRevert(
      address(pool),
      abi.encodeWithSelector(IFluidDexT1.getPricesAndExchangePrices.selector),
      shortRevertData
    );

    vm.expectRevert(FluidDexObservationAggregator.InvalidRevertData.selector);
    vm.prank(keeper);
    aggregator.recordObservation();
  }

  function test_recordObservation_reverts_on_revert_data_too_long() public {
    // Mock the pool to revert with too-long data (300 bytes instead of 292)
    bytes memory longRevertData = new bytes(300);

    vm.mockCallRevert(
      address(pool),
      abi.encodeWithSelector(IFluidDexT1.getPricesAndExchangePrices.selector),
      longRevertData
    );

    vm.expectRevert(FluidDexObservationAggregator.InvalidRevertData.selector);
    vm.prank(keeper);
    aggregator.recordObservation();
  }

  function test_recordObservation_reverts_on_zero_price_from_pool() public {
    bytes memory revertData = abi.encodeWithSelector(
      IFluidDexT1.FluidDexPricesAndExchangeRates.selector,
      IFluidDexT1.PricesAndExchangePrice({
        lastStoredPrice: 0,
        centerPrice: 0,
        upperRange: 0,
        lowerRange: 0,
        geometricMean: 0,
        supplyToken0ExchangePrice: 0,
        borrowToken0ExchangePrice: 0,
        supplyToken1ExchangePrice: 0,
        borrowToken1ExchangePrice: 0
      })
    );

    vm.mockCallRevert(
      address(pool),
      abi.encodeWithSelector(IFluidDexT1.getPricesAndExchangePrices.selector),
      revertData
    );

    vm.expectRevert(FluidDexObservationAggregator.ZeroPriceFromPool.selector);
    vm.prank(keeper);
    aggregator.recordObservation();
  }

  function test_recordObservation_reverts_on_wrong_selector() public {
    // Build revert data with correct length (292 bytes) but wrong selector
    bytes4 wrongSelector = bytes4(keccak256("WrongError()"));
    bytes memory revertData = abi.encodePacked(wrongSelector, new bytes(288));

    vm.mockCallRevert(
      address(pool),
      abi.encodeWithSelector(IFluidDexT1.getPricesAndExchangePrices.selector),
      revertData
    );

    vm.expectRevert(FluidDexObservationAggregator.InvalidRevertData.selector);
    vm.prank(keeper);
    aggregator.recordObservation();
  }

  /* ========== LATEST ROUND DATA TESTS ========== */

  function test_latestRoundData_reverts_with_insufficient_observations() public {
    // No observations recorded yet
    vm.expectRevert(abi.encodeWithSelector(FluidDexObservationAggregator.InsufficientObservations.selector, 0, 3));
    aggregator.latestRoundData();

    // Record 1 observation
    vm.prank(keeper);
    aggregator.recordObservation();

    // Still not enough
    vm.expectRevert(abi.encodeWithSelector(FluidDexObservationAggregator.InsufficientObservations.selector, 1, 3));
    aggregator.latestRoundData();
  }

  function test_latestRoundData_succeeds_with_min_observations() public {
    // Need observations spanning at least twapPeriod
    // twapPeriod = 1800s, minObservationInterval = 60s
    // Need at least 31 observations to span >= 1800s (30 * 60 = 1800)
    uint256 observationsNeeded = (twapPeriod / minObservationInterval) + 1;
    _recordMultipleObservations(observationsNeeded);

    // Should succeed now
    (, int256 answer, , uint256 updatedAt, ) = aggregator.latestRoundData();

    assertGt(answer, 0, "Price should be positive");
    assertGt(updatedAt, 0, "UpdatedAt should be positive");
  }

  function test_latestRoundData_reverts_when_stale() public {
    // Record enough observations to span twapPeriod
    uint256 observationsNeeded = (twapPeriod / minObservationInterval) + 1;
    _recordMultipleObservations(observationsNeeded);

    // Warp past staleness threshold
    vm.warp(block.timestamp + maxStaleness + 1);

    vm.expectRevert(
      abi.encodeWithSelector(FluidDexObservationAggregator.PriceStale.selector, maxStaleness + 1, maxStaleness)
    );
    aggregator.latestRoundData();
  }

  /// @notice Verifies the aggregator price is close to the reference oracle price
  /// @dev In fork tests with vm.warp(), no actual swaps happen on the Fluid DEX pool,
  ///      so `lastStoredPrice` remains constant across all observations.
  ///      This means TWAP equals spot price (all observations have the same price value).
  ///      The test still validates the price calculation logic and comparison to reference.
  function test_latestRoundData_price_is_close_to_reference() public {
    // Record enough observations to span at least twapPeriod
    uint256 observationsNeeded = (twapPeriod / minObservationInterval) + 2;
    _recordMultipleObservations(observationsNeeded);

    _assertAggregatorPriceMatchesReference();
  }

  /* ========== ADMIN FUNCTION TESTS ========== */

  function test_setTwapPeriod_works_for_owner() public {
    uint256 newPeriod = 3600;

    vm.prank(owner);
    aggregator.setTwapPeriod(newPeriod);

    assertEq(aggregator.twapPeriod(), newPeriod, "TwapPeriod should be updated");
  }

  function test_setTwapPeriod_reverts_for_non_owner() public {
    vm.prank(user);
    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("OwnableUnauthorizedAccount(address)")), user));
    aggregator.setTwapPeriod(3600);
  }

  function test_setTwapPeriod_reverts_for_zero() public {
    vm.prank(owner);
    vm.expectRevert(FluidDexObservationAggregator.InvalidTwapPeriod.selector);
    aggregator.setTwapPeriod(0);
  }

  function test_setMinObservationInterval_works_for_owner() public {
    uint256 newInterval = 120;

    vm.prank(owner);
    aggregator.setMinObservationInterval(newInterval);

    assertEq(aggregator.minObservationInterval(), newInterval, "MinObservationInterval should be updated");
  }

  function test_setMinObservationInterval_reverts_for_non_owner() public {
    vm.prank(user);
    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("OwnableUnauthorizedAccount(address)")), user));
    aggregator.setMinObservationInterval(120);
  }

  function test_setMaxStaleness_works_for_owner() public {
    uint256 newStaleness = 600;

    vm.prank(owner);
    aggregator.setMaxStaleness(newStaleness);

    assertEq(aggregator.maxStaleness(), newStaleness, "MaxStaleness should be updated");
  }

  function test_setMaxStaleness_reverts_for_non_owner() public {
    vm.prank(user);
    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("OwnableUnauthorizedAccount(address)")), user));
    aggregator.setMaxStaleness(600);
  }

  function test_setMaxStaleness_reverts_for_zero() public {
    vm.prank(owner);
    vm.expectRevert(FluidDexObservationAggregator.InvalidParameter.selector);
    aggregator.setMaxStaleness(0);
  }

  function test_setVolatilityLimit_works_for_owner() public {
    uint256 newLimit = 500;

    vm.prank(owner);
    aggregator.setVolatilityLimit(newLimit);

    assertEq(aggregator.volatilityLimit(), newLimit, "VolatilityLimit should be updated");
  }

  function test_setVolatilityLimit_reverts_for_non_owner() public {
    vm.prank(user);
    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("OwnableUnauthorizedAccount(address)")), user));
    aggregator.setVolatilityLimit(500);
  }

  function test_setVolatilityLimit_reverts_for_zero() public {
    vm.prank(owner);
    vm.expectRevert(FluidDexObservationAggregator.InvalidParameter.selector);
    aggregator.setVolatilityLimit(0);
  }

  /* ========== KEEPER AUTHORIZATION TESTS ========== */

  function test_setKeeperAuthorization_works_for_owner() public {
    address newKeeper = makeAddr("newKeeper");

    vm.prank(owner);
    aggregator.setKeeperAuthorization(newKeeper, true);

    assertTrue(aggregator.authorizedKeepers(newKeeper), "Keeper should be authorized");

    vm.prank(owner);
    aggregator.setKeeperAuthorization(newKeeper, false);

    assertFalse(aggregator.authorizedKeepers(newKeeper), "Keeper should be revoked");
  }

  function test_setKeeperAuthorization_reverts_for_non_owner() public {
    vm.prank(user);
    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("OwnableUnauthorizedAccount(address)")), user));
    aggregator.setKeeperAuthorization(user, true);
  }

  function test_recordObservation_reverts_for_unauthorized_caller() public {
    vm.prank(user);
    vm.expectRevert(FluidDexObservationAggregator.NotAuthorized.selector);
    aggregator.recordObservation();
  }

  /* ========== CIRCULAR BUFFER TESTS ========== */

  function test_circular_buffer_wraps_correctly() public {
    // Record half of bufferSize observations
    uint256 halfBuffer = bufferSize / 2;
    _recordMultipleObservations(halfBuffer);

    // Verify state before wrap
    assertEq(aggregator.totalObservations(), halfBuffer, "Total observations should be halfBuffer");
    assertEq(aggregator.nextObservationIndex(), halfBuffer, "Next index should be halfBuffer");

    // Warp before next batch
    vm.warp(block.timestamp + minObservationInterval);

    // Record remaining to fill buffer exactly
    _recordMultipleObservations(bufferSize - halfBuffer);

    // Verify buffer is full but not wrapped
    assertEq(aggregator.totalObservations(), bufferSize, "Total observations should be bufferSize");
    assertEq(aggregator.nextObservationIndex(), 0, "Next index should wrap to 0");

    // Record one more to trigger wrap
    vm.warp(block.timestamp + minObservationInterval);
    vm.prank(keeper);
    aggregator.recordObservation();

    // Verify wrap occurred
    assertEq(aggregator.totalObservations(), bufferSize + 1, "Total observations should be bufferSize + 1");
    assertEq(aggregator.nextObservationIndex(), 1, "Next index should be 1 after wrap");

    // Verify oldest observation was overwritten (index 0 now has new timestamp)
    (uint64 timestamp, ) = aggregator.observations(0);
    assertEq(timestamp, block.timestamp, "Observation at index 0 should have current timestamp");
  }

  /* ========== TWAP COMPUTATION TESTS ========== */

  /// @notice Tests that _computeTwap reverts when observations don't span twapPeriod
  function test_computeTwap_reverts_when_span_less_than_twapPeriod() public {
    // Record only 3 observations with minObservationInterval spacing
    // Total time span: 2 * minObservationInterval = 120 seconds (less than twapPeriod = 1800)
    _recordMultipleObservations(3);

    uint256 actualSpan = 2 * minObservationInterval; // 120 seconds
    vm.expectRevert(
      abi.encodeWithSelector(FluidDexObservationAggregator.InvalidTwapSpan.selector, actualSpan, twapPeriod)
    );
    aggregator.latestRoundData();
  }

  /// @notice Tests _computeTwap succeeds when observations span exactly twapPeriod
  function test_computeTwap_succeeds_with_exactly_twapPeriod_span() public {
    // Record exactly enough observations to span twapPeriod
    // twapPeriod = 1800s, minObservationInterval = 60s
    // Need 31 observations: 30 intervals * 60s = 1800s
    uint256 observationsNeeded = (twapPeriod / minObservationInterval) + 1;
    _recordMultipleObservations(observationsNeeded);

    // TWAP should succeed with exactly twapPeriod span
    _assertAggregatorPriceMatchesReference();
  }

  /// @notice Tests _computeTwap count uses bufferSize when totalObservations exceeds it
  function test_computeTwap_count_uses_bufferSize_when_observations_exceed_it() public {
    // Record more observations than bufferSize (triggers wrap)
    _recordMultipleObservations(bufferSize + 5);

    // TWAP should still work correctly after wrap
    _assertAggregatorPriceMatchesReference();
  }

  /// @notice Demonstrates scenario: after a long gap, a single fresh observation
  ///         should NOT be enough to compute TWAP (manipulation risk)
  function test_latestRoundData_reverts_after_gap_with_single_observation() public {
    // 1. Build up a healthy buffer of observations spanning twapPeriod
    uint256 observationsNeeded = (twapPeriod / minObservationInterval) + 2;
    _recordMultipleObservations(observationsNeeded);

    // Verify TWAP works
    _assertAggregatorPriceMatchesReference();

    // 2. Simulate a long gap (e.g., 2 days) - automation stopped
    uint256 gapDuration = 2 days;
    vm.warp(block.timestamp + gapDuration);

    // Verify price is now stale
    vm.expectRevert(
      abi.encodeWithSelector(FluidDexObservationAggregator.PriceStale.selector, gapDuration, maxStaleness)
    );
    aggregator.latestRoundData();

    // 3. Record a single new observation after the gap
    vm.prank(keeper);
    aggregator.recordObservation();

    // 4. SHOULD REVERT: 1 segment is not enough for a secure TWAP (need MIN_SEGMENTS = 2)
    vm.expectRevert(abi.encodeWithSelector(FluidDexObservationAggregator.InsufficientTwapSegments.selector, 1, 2));
    aggregator.latestRoundData();
  }

  /* ========== TWAP MANIPULATION RESISTANCE TESTS ========== */

  function test_twap_manipulation_is_bounded_multiple_rounds() public {
    _testTwapManipulationIsBounded(10);
  }

  function test_twap_manipulation_is_bounded_single_round() public {
    _testTwapManipulationIsBounded(1);
  }

  /* ========== HELPERS ========== */

  /// @notice Helper to test TWAP manipulation is bounded
  /// @param rounds Number of manipulation rounds to attempt
  /// @dev With TWAP-based volatility validation, each observation can only differ from TWAP
  ///      by volatilityLimit. This limits how much an attacker can drift the TWAP.
  ///      With authorized keepers, this attack vector is eliminated entirely.
  function _testTwapManipulationIsBounded(uint256 rounds) internal {
    // 1. Build up a healthy buffer of observations spanning twapPeriod
    uint256 observationsNeeded = (twapPeriod / minObservationInterval) + 2;
    _recordMultipleObservations(observationsNeeded);

    // Get the TWAP price before manipulation
    (, int256 twapPriceBefore, , , ) = aggregator.latestRoundData();

    // Get the current lastStoredPrice from the pool
    uint256 currentLastStoredPrice = _getLastStoredPriceFromPool();

    // 2. Loop - attacker tries to manipulate each observation
    for (uint256 i = 0; i < rounds; i++) {
      // Wait for minimum observation interval
      vm.warp(block.timestamp + minObservationInterval);

      // Try to manipulate by 1% each time
      uint256 manipulatedLastStoredPrice;
      if (aggregator.mainTokenIsToken0()) {
        manipulatedLastStoredPrice = (currentLastStoredPrice * 9900) / 10000; // 1% lower
      } else {
        manipulatedLastStoredPrice = (currentLastStoredPrice * 10100) / 10000; // 1% higher
      }

      // Build the revert data that Fluid DEX would return with manipulated price
      bytes memory revertData = abi.encodeWithSelector(
        IFluidDexT1.FluidDexPricesAndExchangeRates.selector,
        IFluidDexT1.PricesAndExchangePrice({
          lastStoredPrice: manipulatedLastStoredPrice,
          centerPrice: 0,
          upperRange: 0,
          lowerRange: 0,
          geometricMean: 0,
          supplyToken0ExchangePrice: 0,
          borrowToken0ExchangePrice: 0,
          supplyToken1ExchangePrice: 0,
          borrowToken1ExchangePrice: 0
        })
      );

      // Mock the pool to return manipulated price
      vm.mockCallRevert(
        address(pool),
        abi.encodeWithSelector(IFluidDexT1.getPricesAndExchangePrices.selector),
        revertData
      );

      // Record observation with manipulated price
      vm.prank(keeper);
      aggregator.recordObservation();

      // Get TWAP after this manipulation
      // (, int256 twapPriceAfterRound, , , ) = aggregator.latestRoundData();

      // console2.log("--- Round", i + 1, "---");
      // console2.log("  TWAP after round:        ", twapPriceAfterRound);
    }

    // 3. Get final TWAP price after all manipulations
    (, int256 twapPriceAfter, , , ) = aggregator.latestRoundData();

    // Calculate total price change
    uint256 priceDiff;
    if (twapPriceAfter > twapPriceBefore) {
      priceDiff = uint256(twapPriceAfter - twapPriceBefore);
    } else {
      priceDiff = uint256(twapPriceBefore - twapPriceAfter);
    }
    uint256 priceChangePercent = (priceDiff * 10000) / uint256(twapPriceBefore);

    // Verify the TWAP change is bounded by the time-weighted contribution
    // Each observation's max TWAP impact ≈ volatilityLimit * minObservationInterval / twapPeriod
    // For rounds observations, max impact ≈ rounds * volatilityLimit * minObservationInterval / twapPeriod
    uint256 maxExpectedChangeBps = (rounds * volatilityLimit * minObservationInterval) / twapPeriod;

    // console2.log("=== SUMMARY ===");
    // console2.log("TWAP before manipulation:", twapPriceBefore);
    // console2.log("TWAP after round(s):     ", twapPriceAfter);
    // console2.log("Total change (bps):      ", priceChangePercent);
    // console2.log("Max expected change (bps):", maxExpectedChangeBps);

    assertGt(twapPriceBefore, 0, "TWAP before should be positive");
    assertGt(twapPriceAfter, 0, "TWAP after should be positive");
    assertLe(priceChangePercent, maxExpectedChangeBps, "TWAP change should be bounded by time-weighted impact");
  }

  /// @notice Helper to get the current lastStoredPrice from the Fluid DEX pool
  /// @dev Calls getPricesAndExchangePrices() which reverts with the price data
  function _getLastStoredPriceFromPool() internal returns (uint256 lastStoredPrice) {
    // solhint-disable-next-line avoid-low-level-calls
    (bool success, bytes memory data) = address(pool).call(
      abi.encodeWithSelector(IFluidDexT1.getPricesAndExchangePrices.selector)
    );
    require(!success, "Expected revert");
    require(data.length == 292, "Invalid revert data length");

    assembly {
      lastStoredPrice := mload(add(data, 36))
    }
  }

  /// @notice Helper to test volatility revert with a given price multiplier
  /// @param priceMultiplierBps Price multiplier in basis points (e.g., 11000 = 110%, 9000 = 90%)
  /// @param expectedPriceDiffBps Expected price diff in bps (e.g., 999 for 10% increase)
  function _testVolatilityRevert(uint256 priceMultiplierBps, uint256 expectedPriceDiffBps) internal {
    // First, we need to establish a valid TWAP by recording observations spanning twapPeriod
    uint256 observationsNeeded = (twapPeriod / minObservationInterval) + 2;
    _recordMultipleObservations(observationsNeeded);
    vm.warp(block.timestamp + minObservationInterval); // Warp to allow next observation

    // Get the current TWAP price (this is what volatility will be checked against)
    (, uint192 storedPrice) = aggregator.observations(
      aggregator.nextObservationIndex() == 0 ? bufferSize - 1 : aggregator.nextObservationIndex() - 1
    );

    // Calculate target final price based on multiplier
    uint256 targetFinalPrice = (uint256(storedPrice) * priceMultiplierBps) / 10000;

    // Calculate what lastStoredPrice needs to be:
    // - If mainTokenIsToken0: finalPrice = lastStoredPrice (no inversion)
    // - If !mainTokenIsToken0: finalPrice = 1e54 / lastStoredPrice (inverted)
    uint256 mockLastStoredPrice;
    if (aggregator.mainTokenIsToken0()) {
      mockLastStoredPrice = targetFinalPrice;
    } else {
      // Invert back: lastStoredPrice = 1e54 / targetFinalPrice
      mockLastStoredPrice = (1e27 * 1e27) / targetFinalPrice;
    }

    // Build the revert data that Fluid DEX would return
    bytes memory revertData = abi.encodeWithSelector(
      IFluidDexT1.FluidDexPricesAndExchangeRates.selector,
      IFluidDexT1.PricesAndExchangePrice({
        lastStoredPrice: mockLastStoredPrice,
        centerPrice: 0,
        upperRange: 0,
        lowerRange: 0,
        geometricMean: 0,
        supplyToken0ExchangePrice: 0,
        borrowToken0ExchangePrice: 0,
        supplyToken1ExchangePrice: 0,
        borrowToken1ExchangePrice: 0
      })
    );

    // Mock the pool to return our volatile price
    vm.mockCallRevert(
      address(pool),
      abi.encodeWithSelector(IFluidDexT1.getPricesAndExchangePrices.selector),
      revertData
    );

    // Should revert due to volatility (price differs from TWAP by more than volatilityLimit)
    // Use try/catch to allow ±1 tolerance due to double-inversion rounding
    vm.prank(keeper);
    try aggregator.recordObservation() {
      revert("Expected PriceVolatilityTooHigh revert");
    } catch (bytes memory reason) {
      bytes4 selector = bytes4(reason);
      assertEq(selector, FluidDexObservationAggregator.PriceVolatilityTooHigh.selector, "Wrong error selector");

      // Decode the error parameters
      (uint256 actualPriceDiff, uint256 actualLimit) = abi.decode(_slice(reason, 4), (uint256, uint256));

      // Allow ±1 tolerance for priceDiff due to rounding from double-inversion
      assertApproxEqAbs(actualPriceDiff, expectedPriceDiffBps, 1, "priceDiff mismatch");
      assertEq(actualLimit, volatilityLimit, "volatilityLimit should match");
    }
  }

  /// @notice Helper to record multiple observations with proper time spacing
  /// @dev We don't warp after the last observation to ensure latestRoundData() is called
  ///      with timeSinceLast = 0, avoiding potential PriceStale reverts in tests.
  function _recordMultipleObservations(uint256 count) internal {
    for (uint256 i = 0; i < count; i++) {
      vm.prank(keeper);
      aggregator.recordObservation();
      if (i < count - 1) {
        vm.warp(block.timestamp + minObservationInterval);
      }
    }
  }

  /// @notice Helper to assert aggregator price matches reference oracle within acceptable deviation
  function _assertAggregatorPriceMatchesReference() internal view {
    (, int256 twapPrice, , , ) = aggregator.latestRoundData();
    (, int256 referencePrice, , , ) = referenceOracle.latestRoundData();

    assertGt(twapPrice, 0, "TWAP price should be positive");
    assertGt(referencePrice, 0, "Reference price should be positive");

    uint256 diff = twapPrice > referencePrice
      ? uint256(twapPrice - referencePrice)
      : uint256(referencePrice - twapPrice);
    uint256 deviation = (diff * 10000) / uint256(referencePrice);

    assertLe(deviation, maxDeviation, "Price deviation should be within acceptable range");
  }

  /// @notice Helper to slice bytes starting from an offset
  function _slice(bytes memory data, uint256 start) internal pure returns (bytes memory) {
    require(start <= data.length, "Slice out of bounds");
    uint256 length = data.length - start;
    bytes memory result = new bytes(length);
    for (uint256 i; i < length; ++i) {
      result[i] = data[start + i];
    }
    return result;
  }
}
