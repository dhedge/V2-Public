// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {FluidDexTWAPAggregator} from "contracts/priceAggregators/FluidDexTWAPAggregator.sol";
import {IAggregatorV3Interface} from "contracts/interfaces/IAggregatorV3Interface.sol";
import {IFluidDexFactory} from "contracts/interfaces/fluid/IFluidDexFactory.sol";
import {IFluidDexT1} from "contracts/interfaces/fluid/IFluidDexT1.sol";

/// @dev IMPORTANT: The Fluid DEX oracle requires activation and historical price data from swaps.
///      Fluid DEX error codes (appear as custom error FluidDexError(uint256) 0x2fee3e0e with hex-encoded code):
///      - 51050 (0xc76a) DexT1__InsufficientOracleData: TWAP period exceeds available swap history.
///      - 51066 (0xc77a) DexT1__OracleNotActive: Oracle disabled (bit 195 in dexVariables is 0).
///      The test setup activates the oracle by pranking the factory owner.
abstract contract FluidDexTWAPAggregatorTestSetup is Test {
  IFluidDexT1 public immutable pool;
  address public immutable mainToken;
  IAggregatorV3Interface public immutable pairTokenUsdAggregator;
  uint256 public immutable twapPeriod;

  // Reference oracle for price comparison (e.g., Chainlink oracle for mainToken)
  IAggregatorV3Interface public immutable referenceOracle;

  // Maximum acceptable deviation between TWAP price and reference price (in basis points, e.g., 100 = 1%)
  uint256 public immutable maxDeviation;

  FluidDexTWAPAggregator public aggregator;

  constructor(
    IFluidDexT1 _pool,
    address _mainToken,
    IAggregatorV3Interface _pairTokenUsdAggregator,
    uint256 _twapPeriod,
    IAggregatorV3Interface _referenceOracle,
    uint256 _maxDeviation
  ) {
    pool = _pool;
    mainToken = _mainToken;
    pairTokenUsdAggregator = _pairTokenUsdAggregator;
    twapPeriod = _twapPeriod;
    referenceOracle = _referenceOracle;
    maxDeviation = _maxDeviation;
  }

  function setUp() public virtual {
    // Activate the oracle on the Fluid DEX pool by pranking the factory owner
    _activateFluidDexOracle();

    // Deploy the FluidDexTWAPAggregator
    aggregator = new FluidDexTWAPAggregator(pool, mainToken, pairTokenUsdAggregator, twapPeriod);
  }

  /// @notice Activates the Fluid DEX oracle by pranking as the factory owner.
  /// @dev Required because Fluid DEX pools have oracle disabled by default (bit 195 = 0).
  ///      When oracle is OFF: swaps update dexVariables (lastPrice, timestamps) but NOT the _oracle buffer.
  ///      TWAP is then limited to (block.timestamp - lastSwapTime) + lastTimestampDifBetweenLastToLastPrice,
  ///      i.e., only 2 price points spanning time since the second-to-last swap.
  ///      When oracle is ON: each swap writes to circular buffer (8192 entries), enabling longer TWAPs.
  function _activateFluidDexOracle() internal {
    // Get the factory address from the pool constants
    IFluidDexT1.ConstantViews memory constants = pool.constantsView();
    IFluidDexFactory factory = IFluidDexFactory(constants.factory);

    // Get the factory owner (who has global auth by default)
    address factoryOwner = factory.owner();

    // Prank as factory owner and activate the oracle
    vm.prank(factoryOwner);
    pool.toggleOracleActivation(true);
  }

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
    assertEq(aggregator.twapPeriod(), twapPeriod, "TwapPeriod should match");

    // Verify token0/token1 identification and pairToken derivation
    IFluidDexT1.ConstantViews memory constants = pool.constantsView();
    address token0 = constants.token0;
    address token1 = constants.token1;

    assertTrue(aggregator.mainToken() == token0 || aggregator.mainToken() == token1, "MainToken should be in pool");

    if (aggregator.mainTokenIsToken0()) {
      assertEq(aggregator.mainToken(), token0, "If mainTokenIsToken0, mainToken should be token0");
      assertEq(aggregator.pairToken(), token1, "If mainTokenIsToken0, pairToken should be token1");
    } else {
      assertEq(aggregator.mainToken(), token1, "If not mainTokenIsToken0, mainToken should be token1");
      assertEq(aggregator.pairToken(), token0, "If not mainTokenIsToken0, pairToken should be token0");
    }
  }

  function test_latestRoundData_returns_price() public view {
    (, int256 answer, , uint256 updatedAt, ) = aggregator.latestRoundData();

    // Price should be positive
    assertGt(answer, 0, "Price should be positive");

    // UpdatedAt should be recent (within last day for fork tests)
    assertGt(updatedAt, block.timestamp - 1 days, "UpdatedAt should be recent");
  }

  function test_price_is_close_to_reference_oracle() public {
    (, int256 twapPrice, , , ) = aggregator.latestRoundData();
    (, int256 referencePrice, , , ) = referenceOracle.latestRoundData();

    // Both prices should be positive
    assertGt(twapPrice, 0, "TWAP price should be positive");
    assertGt(referencePrice, 0, "Reference price should be positive");

    // Calculate deviation in basis points
    // deviation = |twapPrice - referencePrice| * 10000 / referencePrice
    uint256 diff = twapPrice > referencePrice
      ? uint256(twapPrice - referencePrice)
      : uint256(referencePrice - twapPrice);
    uint256 deviation = (diff * 10000) / uint256(referencePrice);

    // Log prices for debugging
    emit log_named_int("TWAP Price", twapPrice);
    emit log_named_int("Reference Price", referencePrice);
    emit log_named_uint("Deviation (bps)", deviation);

    assertLe(deviation, maxDeviation, "Price deviation should be within acceptable range");
  }
}
