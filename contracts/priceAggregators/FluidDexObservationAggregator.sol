//
//        __  __    __  ________  _______    ______   ________
//       /  |/  |  /  |/        |/       \  /      \ /        |
//   ____$$ |$$ |  $$ |$$$$$$$$/ $$$$$$$  |/$$$$$$  |$$$$$$$$/
//  /    $$ |$$ |__$$ |$$ |__    $$ |  $$ |$$ | _$$/ $$ |__
// /$$$$$$$ |$$    $$ |$$    |   $$ |  $$ |$$ |/    |$$    |
// $$ |  $$ |$$$$$$$$ |$$$$$/    $$ |  $$ |$$ |$$$$ |$$$$$/
// $$ \__$$ |$$ |  $$ |$$ |_____ $$ |__$$ |$$ \__$$ |$$ |_____
// $$    $$ |$$ |  $$ |$$       |$$    $$/ $$    $$/ $$       |
//  $$$$$$$/ $$/   $$/ $$$$$$$$/ $$$$$$$/   $$$$$$/  $$$$$$$$/
//
// dHEDGE DAO - https://dhedge.org
//
// Copyright (c) dHEDGE DAO
//
// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/v5/contracts/access/Ownable.sol";
import {IAggregatorV3Interface} from "../interfaces/IAggregatorV3Interface.sol";
import {IFluidDexT1} from "../interfaces/fluid/IFluidDexT1.sol";

/// @title Fluid DEX Observation Aggregator
/// @notice Records price observations from Fluid DEX pools and computes TWAP
/// @dev Works around Fluid DEX pools where the built-in oracle cannot be activated.
///      An external automation (e.g., Chainlink Automation, Gelato) must call `recordObservation()`
///      periodically to populate the observation buffer. The TWAP is then computed from stored observations.
///
/// @dev ARCHITECTURE:
/// - Uses a circular buffer of observations (timestamp, price) with configurable capacity
/// - `recordObservation()` fetches current price from Fluid DEX via `getPricesAndExchangePrices()`
/// - `latestRoundData()` computes TWAP over the configured period from stored observations
/// - Price source: `lastStoredPrice` from Fluid DEX (1e27 precision, normalized ratio)
///
/// @dev PRICE PRECISION:
/// - Fluid DEX prices are in 1e27 (normalized, dimensionless ratio of token1/token0)
/// - Output is Chainlink-compatible 8 decimals USD price
///
/// @dev TRUST MODEL:
/// - Volatility check validates new observations against computed TWAP
/// - BOOTSTRAP PHASE: First observations (before TWAP is computable) are NOT validated.
///   The initial observations MUST be recorded by a trusted party (e.g., contract deployer).
/// - RECOVERY PHASE: After a gap where TWAP becomes invalid (stale observations),
///   the first recovery observation is NOT validated. Recovery MUST be performed by a trusted party.
contract FluidDexObservationAggregator is Ownable, IAggregatorV3Interface {
  /// @notice Observation data point
  struct Observation {
    uint64 timestamp;
    uint192 price; // Price in 1e27 precision (fits in 192 bits)
  }

  /// @notice Fluid DEX prices precision
  uint256 private constant FLUID_PRICE_PRECISION = 1e27;

  /// @notice Minimum segments required for TWAP calculation (n segments require n+1 observation points)
  uint256 private constant MIN_SEGMENTS = 2;

  /// @notice Minimum observation points required (n segments need n+1 points)
  uint256 private constant MIN_OBSERVATIONS = MIN_SEGMENTS + 1;

  /// @notice Maximum observation buffer size
  uint256 private constant MAX_BUFFER_SIZE = 8192;

  /// @notice Maximum TWAP period (1 day)
  uint256 private constant MAX_TWAP_PERIOD = 1 days;

  /// @notice Fluid DEX pool address
  IFluidDexT1 public immutable pool;

  /// @notice The token for which to get the TWAP price
  address public immutable mainToken;

  /// @notice The paired token used for price calculation
  address public immutable pairToken;

  /// @notice Chainlink USD aggregator of the pair token
  IAggregatorV3Interface public immutable pairTokenUsdAggregator;

  /// @notice True if mainToken is token0 in the pool
  bool public immutable mainTokenIsToken0;

  /// @notice Size of the circular observation buffer
  uint256 public immutable bufferSize;

  /// @notice TWAP period in seconds (e.g., 1800 for 30 minutes)
  uint256 public twapPeriod;

  /// @notice Minimum interval between observations in seconds
  uint256 public minObservationInterval;

  /// @notice Maximum allowed time since last observation for price to be valid
  uint256 public maxStaleness;

  /// @notice Maximum acceptable volatility between consecutive observations (basis points, e.g., 500 = 5%)
  uint256 public volatilityLimit;

  /// @notice Circular buffer of observations
  Observation[] public observations;

  /// @notice Index of the next observation to write (circular)
  uint256 public nextObservationIndex;

  /// @notice Total number of observations recorded (may exceed buffer size due to wrap-around)
  uint256 public totalObservations;

  /// @notice Mapping of authorized keeper addresses that can call recordObservation()
  mapping(address => bool) public authorizedKeepers;

  // Events
  event ObservationRecorded(uint192 price);
  event TwapPeriodUpdated(uint256 oldPeriod, uint256 newPeriod);
  event MinObservationIntervalUpdated(uint256 oldInterval, uint256 newInterval);
  event MaxStalenessUpdated(uint256 oldStaleness, uint256 newStaleness);
  event VolatilityLimitUpdated(uint256 oldLimit, uint256 newLimit);
  event KeeperAuthorizationUpdated(address indexed keeper, bool authorized);

  // Errors
  error InvalidParameter();
  error InvalidBufferSize();
  error InvalidTwapPeriod();
  error ObservationTooSoon(uint256 timeSinceLast, uint256 minInterval);
  error PriceVolatilityTooHigh(uint256 priceDiff, uint256 limit);
  error InsufficientObservations(uint256 available, uint256 required);
  error PriceStale(uint256 timeSinceLast, uint256 maxStaleness);
  error InvalidTwapSpan(uint256 actualSpan, uint256 requiredSpan);
  error InsufficientTwapSegments(uint256 available, uint256 required);
  error UnexpectedSuccess();
  error InvalidRevertData();
  error ZeroPriceFromPool();
  error NotAuthorized();

  modifier onlyAuthorizedKeeper() {
    if (!authorizedKeepers[msg.sender]) {
      revert NotAuthorized();
    }
    _;
  }

  /// @param _owner Contract owner address
  /// @param _pool Fluid DEX pool address
  /// @param _mainToken The token for which to get the TWAP price
  /// @param _pairTokenUsdAggregator Chainlink USD aggregator of the pair token
  /// @param _twapPeriod TWAP period in seconds (e.g., 1800 for 30 minutes)
  /// @param _minObservationInterval Minimum interval between observations in seconds
  /// @param _maxStaleness Maximum allowed time since last observation
  /// @param _volatilityLimit Maximum price change between observations (basis points)
  /// @param _bufferSize Number of observations to store
  constructor(
    address _owner,
    IFluidDexT1 _pool,
    address _mainToken,
    IAggregatorV3Interface _pairTokenUsdAggregator,
    uint256 _twapPeriod,
    uint256 _minObservationInterval,
    uint256 _maxStaleness,
    uint256 _volatilityLimit,
    uint256 _bufferSize
  ) Ownable(_owner) {
    if (address(_pool) == address(0)) revert InvalidParameter();
    if (_mainToken == address(0)) revert InvalidParameter();
    if (address(_pairTokenUsdAggregator) == address(0)) revert InvalidParameter();
    if (_pairTokenUsdAggregator.decimals() != 8) revert InvalidParameter();
    if (_twapPeriod == 0 || _twapPeriod > MAX_TWAP_PERIOD) revert InvalidTwapPeriod();
    if (_maxStaleness == 0) revert InvalidParameter();
    if (_volatilityLimit == 0) revert InvalidParameter();
    if (_bufferSize < MIN_OBSERVATIONS || _bufferSize > MAX_BUFFER_SIZE) revert InvalidBufferSize();

    IFluidDexT1.ConstantViews memory constants = _pool.constantsView();
    address token0 = constants.token0;
    address token1 = constants.token1;

    if (_mainToken != token0 && _mainToken != token1) revert InvalidParameter();

    pool = _pool;
    mainToken = _mainToken;
    pairTokenUsdAggregator = _pairTokenUsdAggregator;
    twapPeriod = _twapPeriod;
    minObservationInterval = _minObservationInterval;
    maxStaleness = _maxStaleness;
    volatilityLimit = _volatilityLimit;

    if (_mainToken == token0) {
      mainTokenIsToken0 = true;
      pairToken = token1;
    } else {
      mainTokenIsToken0 = false;
      pairToken = token0;
    }

    bufferSize = _bufferSize;

    // Initialize observation buffer
    for (uint256 i; i < _bufferSize; ++i) {
      observations.push(Observation({timestamp: 0, price: 0}));
    }
  }

  /* ========== VIEWS ========== */

  function decimals() external pure override returns (uint8) {
    return 8;
  }

  /// @notice Get the latest round data. Should be the same format as Chainlink aggregator.
  /// @return roundId The round ID (always 0).
  /// @return answer The USD price of mainToken with 8 decimals.
  /// @return startedAt Timestamp of when the round started (always 0).
  /// @return updatedAt Timestamp of the latest observation.
  /// @return answeredInRound The round ID of the round in which the answer was computed (always 0).
  function latestRoundData()
    external
    view
    override
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
  {
    if (totalObservations < MIN_OBSERVATIONS) {
      revert InsufficientObservations(totalObservations, MIN_OBSERVATIONS);
    }

    Observation memory latestObs = observations[_getLatestIndex()];

    // Check staleness
    uint256 timeSinceLast = block.timestamp - latestObs.timestamp;
    if (timeSinceLast > maxStaleness) {
      revert PriceStale(timeSinceLast, maxStaleness);
    }

    // Compute TWAP from observations
    uint256 twapPrice = _computeTwap();

    // Get USD price of pair token from Chainlink (8 decimals)
    (, int256 pairUsdPrice, , , ) = pairTokenUsdAggregator.latestRoundData();

    // Calculate USD price of mainToken:
    // mainToken USD price = (pairToken per mainToken) * (pairToken USD price)
    // Since twapPrice is in 1e27 and pairUsdPrice is in 1e8:
    // answer = twapPrice * pairUsdPrice / 1e27
    answer = (int256(twapPrice) * pairUsdPrice) / int256(FLUID_PRICE_PRECISION);

    // Always use twap timestamp
    updatedAt = latestObs.timestamp;

    return (0, answer, 0, updatedAt, 0);
  }

  /// @notice Get the current price from Fluid DEX pool (without storing)
  /// @dev Used by automation contracts to check if observation is needed.
  ///      Not marked as view because internal call uses .call() which compiler
  ///      considers potentially state-modifying, even though it only reads.
  /// @return price Current price in 1e27 precision
  function getCurrentPrice() external returns (uint256 price) {
    return _fetchFluidDexPrice();
  }

  /// @notice Get the latest stored observation
  /// @dev Returns zero values if no observations recorded yet
  /// @return timestamp Timestamp of latest observation
  /// @return price Price at latest observation (1e27 precision)
  function getLatestObservation() external view returns (uint64 timestamp, uint192 price) {
    Observation memory obs = observations[_getLatestIndex()];
    return (obs.timestamp, obs.price);
  }

  /* ========== MUTATIVE FUNCTIONS ========== */

  /// @notice Record a new price observation from the Fluid DEX pool
  /// @dev Protected by minObservationInterval and volatility check against TWAP.
  /// @dev WARNING: During bootstrap (insufficient observations) or recovery (after staleness gap),
  ///      the volatility check is skipped. These phases require trusted callers.
  function recordObservation() external onlyAuthorizedKeeper {
    // Check minimum interval since last observation
    if (totalObservations > 0) {
      uint256 latestIndex = _getLatestIndex();
      uint256 timeSinceLast = block.timestamp - observations[latestIndex].timestamp;
      if (timeSinceLast < minObservationInterval) {
        revert ObservationTooSoon(timeSinceLast, minObservationInterval);
      }
    }

    // Fetch current price from Fluid DEX
    uint256 currentPrice = _fetchFluidDexPrice();

    // Check volatility against TWAP if available (bootstrap phase skips this check)
    (bool twapAvailable, uint256 twapPrice) = _tryComputeTwap();

    if (twapAvailable) {
      uint256 priceDiff;
      if (currentPrice > twapPrice) {
        priceDiff = ((currentPrice - twapPrice) * 10000) / twapPrice;
      } else {
        priceDiff = ((twapPrice - currentPrice) * 10000) / twapPrice;
      }

      if (priceDiff > volatilityLimit) {
        revert PriceVolatilityTooHigh(priceDiff, volatilityLimit);
      }
    }

    // Store observation
    observations[nextObservationIndex] = Observation({
      timestamp: uint64(block.timestamp),
      price: uint192(currentPrice)
    });

    // Advance circular buffer index
    nextObservationIndex = (nextObservationIndex + 1) % bufferSize;
    totalObservations++;

    emit ObservationRecorded(uint192(currentPrice));
  }

  /* ========== ADMIN FUNCTIONS ========== */

  /// @notice Update the TWAP period
  function setTwapPeriod(uint256 _twapPeriod) external onlyOwner {
    if (_twapPeriod == 0 || _twapPeriod > MAX_TWAP_PERIOD) revert InvalidTwapPeriod();
    emit TwapPeriodUpdated(twapPeriod, _twapPeriod);
    twapPeriod = _twapPeriod;
  }

  /// @notice Update the minimum observation interval
  function setMinObservationInterval(uint256 _minObservationInterval) external onlyOwner {
    emit MinObservationIntervalUpdated(minObservationInterval, _minObservationInterval);
    minObservationInterval = _minObservationInterval;
  }

  /// @notice Update the maximum staleness
  function setMaxStaleness(uint256 _maxStaleness) external onlyOwner {
    if (_maxStaleness == 0) revert InvalidParameter();
    emit MaxStalenessUpdated(maxStaleness, _maxStaleness);
    maxStaleness = _maxStaleness;
  }

  /// @notice Update the volatility limit
  function setVolatilityLimit(uint256 _volatilityLimit) external onlyOwner {
    if (_volatilityLimit == 0) revert InvalidParameter();
    emit VolatilityLimitUpdated(volatilityLimit, _volatilityLimit);
    volatilityLimit = _volatilityLimit;
  }

  /// @notice Authorize or revoke a keeper address
  /// @param _keeper The address of the keeper
  /// @param _authorized True to authorize, false to revoke
  function setKeeperAuthorization(address _keeper, bool _authorized) external onlyOwner {
    authorizedKeepers[_keeper] = _authorized;

    emit KeeperAuthorizationUpdated(_keeper, _authorized);
  }

  /* ========== INTERNAL FUNCTIONS ========== */

  /// @notice Fetch the current price from Fluid DEX
  /// @dev Calls getPricesAndExchangePrices() which reverts with price data
  function _fetchFluidDexPrice() internal returns (uint256 price) {
    // getPricesAndExchangePrices() reverts with FluidDexPricesAndExchangeRates(PricesAndExchangePrice)
    // We need to catch and decode the revert data
    // solhint-disable-next-line avoid-low-level-calls
    (bool success, bytes memory data) = address(pool).call(
      abi.encodeWithSelector(IFluidDexT1.getPricesAndExchangePrices.selector)
    );

    // This call should always revert with the price data
    if (success) revert UnexpectedSuccess();

    // Format: 4 bytes selector + 9 × 32 bytes struct = 292 bytes exactly
    if (data.length != 292) revert InvalidRevertData();

    uint256 lastStoredPrice;
    bytes4 selector;
    assembly {
      // Memory layout: 32 bytes length prefix, then 4 bytes selector, then struct fields
      // Struct fields are packed directly (no offset pointer for static structs)
      selector := mload(add(data, 32))
      lastStoredPrice := mload(add(data, 36))
    }

    if (selector != IFluidDexT1.FluidDexPricesAndExchangeRates.selector) revert InvalidRevertData();

    // Sanity check: pool should never return zero price
    if (lastStoredPrice == 0) revert ZeroPriceFromPool();

    // lastStoredPrice is token1/token0 price in 1e27
    // If mainToken is token0, we want token1/token0 (how much token1 for 1 token0)
    // If mainToken is token1, we want token0/token1 (how much token0 for 1 token1)
    if (mainTokenIsToken0) {
      // price is already token1/token0
      price = lastStoredPrice;
    } else {
      // Invert: token0/token1 = 1e54 / (token1/token0)
      price = (FLUID_PRICE_PRECISION * FLUID_PRICE_PRECISION) / lastStoredPrice;
    }
  }

  /// @notice Compute TWAP from stored observations
  /// @dev Caller must ensure totalObservations >= MIN_OBSERVATIONS. Reverts if TWAP cannot be computed.
  function _computeTwap() internal view returns (uint256) {
    (uint256 twap, uint256 cumulativeTime, uint256 segmentsInWindow) = _computeTwapCore();

    if (cumulativeTime != twapPeriod) {
      revert InvalidTwapSpan(cumulativeTime, twapPeriod);
    }

    if (segmentsInWindow < MIN_SEGMENTS) {
      revert InsufficientTwapSegments(segmentsInWindow, MIN_SEGMENTS);
    }

    return twap;
  }

  /// @notice Try to compute TWAP from stored observations
  /// @dev Returns (false, 0) if not enough observations or insufficient time span
  /// @return success Whether TWAP was successfully computed
  /// @return twap The computed TWAP (only valid if success is true)
  function _tryComputeTwap() internal view returns (bool success, uint256 twap) {
    if (totalObservations < MIN_OBSERVATIONS) {
      return (false, 0);
    }

    (uint256 _twap, uint256 cumulativeTime, uint256 segmentsInWindow) = _computeTwapCore();

    if (cumulativeTime != twapPeriod || segmentsInWindow < MIN_SEGMENTS) {
      return (false, 0);
    }

    return (true, _twap);
  }

  /// @notice Core TWAP computation logic
  /// @dev Returns raw values without reverting, allowing callers to handle errors appropriately
  /// @return twap The computed TWAP (may be invalid if cumulativeTime != twapPeriod)
  /// @return cumulativeTime Total time span covered by observations
  /// @return segmentsInWindow Number of segments contributing to TWAP
  function _computeTwapCore() internal view returns (uint256 twap, uint256 cumulativeTime, uint256 segmentsInWindow) {
    // Determine how many observations to consider:
    // - If buffer hasn't wrapped yet: use all observations (totalObservations)
    // - If buffer has wrapped: use bufferSize (we only have that many valid slots)
    uint256 count = totalObservations < bufferSize ? totalObservations : bufferSize;

    // Get index of the most recent observation
    uint256 latestIndex = _getLatestIndex();
    Observation memory latestObs = observations[latestIndex];

    // Calculate the cutoff time for TWAP window
    // Example: if latestObs.timestamp = 2000 and twapPeriod = 1800
    //          then targetTime = 200 (we only want prices from timestamp 200 onwards)
    uint256 targetTime = latestObs.timestamp - twapPeriod;

    // Accumulators for time-weighted average
    uint256 cumulativePrice; // Sum of (price × duration)

    // Start from the latest observation
    uint256 currentIndex = latestIndex;
    Observation memory currentObs = latestObs;

    // Walk backwards through the circular buffer
    // We iterate count-1 times because we're looking at SEGMENTS between observations
    // (n observations create n-1 segments)
    for (uint256 i; i < count - 1; ++i) {
      // Calculate previous index (wrap around if at 0)
      uint256 prevIndex = currentIndex == 0 ? bufferSize - 1 : currentIndex - 1;
      Observation memory prevObs = observations[prevIndex];

      // Defensive check: should never hit uninitialized slot given count is bounded by totalObservations
      assert(prevObs.timestamp != 0);

      // Count each segment that contributes to the TWAP
      segmentsInWindow++;

      uint256 timeWeight;
      if (prevObs.timestamp <= targetTime) {
        // PARTIAL SEGMENT: prevObs is before our target window
        // Only count the portion from targetTime to currentObs.timestamp
        //
        // Timeline:  [prevObs]----[targetTime]=====[currentObs]
        //                              ↑___________↑
        //                              only this part counts
        timeWeight = currentObs.timestamp - targetTime;
        cumulativePrice += currentObs.price * timeWeight;
        cumulativeTime += timeWeight;
        break; // We've reached the edge of our window, stop here
      } else {
        // FULL SEGMENT: entire segment is within our window
        //
        // Timeline:  [targetTime]...[prevObs]=====[currentObs]
        //                              ↑__________↑
        //                              full segment counts
        timeWeight = currentObs.timestamp - prevObs.timestamp;
        cumulativePrice += currentObs.price * timeWeight;
        cumulativeTime += timeWeight;

        // Move to the previous observation for next iteration
        currentObs = prevObs;
        currentIndex = prevIndex;
      }
    }

    // Return computed values - caller decides whether to revert
    if (cumulativeTime > 0) {
      twap = cumulativePrice / cumulativeTime;
    }
  }

  /// @notice Get the index of the latest observation in the circular buffer
  function _getLatestIndex() internal view returns (uint256) {
    return nextObservationIndex == 0 ? bufferSize - 1 : nextObservationIndex - 1;
  }
}
