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
// Copyright (c) 2026 dHEDGE DAO
//
// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {IAggregatorV3Interface} from "../interfaces/IAggregatorV3Interface.sol";
import {IFluidDexT1} from "../interfaces/fluid/IFluidDexT1.sol";

/// @title Fluid DEX TWAP USD price aggregator.
/// @notice Returns the USD price of a token using Fluid DEX TWAP oracle.
/// @dev This should have `latestRoundData` function as Chainlink pricing oracle.
///
/// @dev FLUID DEX ORACLE REQUIREMENTS:
///
/// The pool's oracle must be activated via `toggleOracleActivation(true)` by a pool admin.
/// This is a prerequisite for TWAP functionality.
///
/// When oracle is OFF (default):
/// - Swaps still update `dexVariables` (lastPrice, lastToLastPrice, timestamps)
/// - But `_oracle` buffer remains empty - no historical data is recorded
/// - TWAP is limited to: (block.timestamp - lastSwapTime) + lastTimestampDifBetweenLastToLastPrice
/// - This provides only 2 price points, limiting TWAP to time since the second-to-last swap
///
/// When oracle is ON:
/// - Each swap writes to `_oracle` circular buffer (capacity: 8192 entries)
/// - Buffer stores time differences and price change percentages
/// - After sufficient swap activity, requested TWAP period becomes reliably available
contract FluidDexTWAPAggregator is IAggregatorV3Interface {
  /// @notice Fluid DEX oracle returns prices in 1e27 precision
  uint256 private constant FLUID_PRICE_PRECISION = 1e27;

  /// @notice Fluid DEX pool address
  IFluidDexT1 public immutable pool;
  /// @notice The token for which to get the TWAP price
  address public immutable mainToken;
  /// @notice The paired token used for price calculation
  address public immutable pairToken;
  /// @notice Chainlink USD aggregator of the pair token
  IAggregatorV3Interface public immutable pairTokenUsdAggregator;
  /// @notice TWAP period in seconds (e.g., 1800 for 30 minutes)
  uint256 public immutable twapPeriod;
  /// @notice True if mainToken is token0 in the pool
  bool public immutable mainTokenIsToken0;

  /// @param _pool Fluid DEX pool address
  /// @param _mainToken The token for which to get the TWAP price
  /// @param _pairTokenUsdAggregator Chainlink USD aggregator of the pair token
  /// @param _twapPeriod TWAP period in seconds (e.g., 1800 for 30 minutes)
  constructor(
    IFluidDexT1 _pool,
    address _mainToken,
    IAggregatorV3Interface _pairTokenUsdAggregator,
    uint256 _twapPeriod
  ) {
    require(address(_pool) != address(0), "pool cannot be 0");
    require(_mainToken != address(0), "mainToken cannot be 0");
    require(address(_pairTokenUsdAggregator) != address(0), "aggregator cannot be 0");
    require(_pairTokenUsdAggregator.decimals() == 8, "aggregator must have 8 decimals");
    require(_twapPeriod > 0, "twapPeriod must be > 0");

    IFluidDexT1.ConstantViews memory constants = _pool.constantsView();
    address token0 = constants.token0;
    address token1 = constants.token1;

    require(_mainToken == token0 || _mainToken == token1, "mainToken not in pool");

    pool = _pool;
    mainToken = _mainToken;
    twapPeriod = _twapPeriod;
    pairTokenUsdAggregator = _pairTokenUsdAggregator;

    if (_mainToken == token0) {
      mainTokenIsToken0 = true;
      pairToken = token1;
    } else {
      mainTokenIsToken0 = false;
      pairToken = token0;
    }
  }

  function decimals() external pure override returns (uint8) {
    return 8;
  }

  /// @notice Get the latest round data. Should be the same format as Chainlink aggregator.
  /// @return roundId The round ID (always 0).
  /// @return answer The USD price of mainToken with 8 decimals.
  /// @return startedAt Timestamp of when the round started (always 0).
  /// @return updatedAt Timestamp from the pair token's Chainlink aggregator.
  /// @return answeredInRound The round ID of the round in which the answer was computed (always 0).
  function latestRoundData()
    external
    view
    override
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
  {
    // Get TWAP from Fluid DEX oracle
    uint256[] memory secondsAgos = new uint256[](1);
    secondsAgos[0] = twapPeriod;

    (IFluidDexT1.Oracle[] memory twaps, ) = pool.oraclePrice(secondsAgos);

    // Fluid DEX TWAP explanation:
    // twap1by0 = amount of token1 per token0 (normalized to 1e27)
    // twap0by1 = amount of token0 per token1 (normalized to 1e27)
    //
    // The prices are already normalized: 1e27 represents a 1:1 ratio between tokens
    // regardless of their actual decimals.
    //
    // Example: USDe (18 dec) / USDT (6 dec)
    // twap1by0 ≈ 1e27 means 1 USDe ≈ 1 USDT
    uint256 twapPrice = mainTokenIsToken0 ? twaps[0].twap1by0 : twaps[0].twap0by1;

    // Get USD price of pair token from Chainlink (8 decimals)
    int256 pairUsdPrice;
    (, pairUsdPrice, , updatedAt, ) = pairTokenUsdAggregator.latestRoundData();

    // Calculate USD price of mainToken:
    // mainToken USD price = (pairToken per mainToken) * (pairToken USD price)
    //
    // Since twapPrice is in 1e27 (representing pairToken/mainToken ratio),
    // and pairUsdPrice is in 1e8 (Chainlink 8 decimals):
    // answer = twapPrice * pairUsdPrice / 1e27
    answer = (int256(twapPrice) * pairUsdPrice) / int256(FLUID_PRICE_PRECISION);

    return (0, answer, 0, updatedAt, 0);
  }
}
