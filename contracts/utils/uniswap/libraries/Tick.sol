// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "./LowGasSafeMath.sol";
import "./SafeCast.sol";

import "./TickMath.sol";
import "./LiquidityMath.sol";

/// @title Tick
/// @notice Contains functions for managing tick processes and relevant calculations

/// Ithil to modify it, since it does not have access to storage arrays
library Tick {
  using LowGasSafeMath for int256;
  using SafeCast for int256;

  // info stored for each initialized individual tick
  struct Info {
    // the total position liquidity that references this tick
    uint128 liquidityGross;
    // amount of net liquidity added (subtracted) when tick is crossed from left to right (right to left),
    int128 liquidityNet;
    // fee growth per unit of liquidity on the _other_ side of this tick (relative to the current tick)
    // only has relative meaning, not absolute — the value depends on when the tick is initialized
    uint256 feeGrowthOutside0X128;
    uint256 feeGrowthOutside1X128;
    // the cumulative tick value on the other side of the tick
    int56 tickCumulativeOutside;
    // the seconds per unit of liquidity on the _other_ side of this tick (relative to the current tick)
    // only has relative meaning, not absolute — the value depends on when the tick is initialized
    uint160 secondsPerLiquidityOutsideX128;
    // the seconds spent on the other side of the tick (relative to the current tick)
    // only has relative meaning, not absolute — the value depends on when the tick is initialized
    uint32 secondsOutside;
    // true iff the tick is initialized, i.e. the value is exactly equivalent to the expression liquidityGross != 0
    // these 8 bits are set to prevent fresh sstores when crossing newly initialized ticks
    bool initialized;
  }

  /// @notice Derives max liquidity per tick from given tick spacing
  /// @dev Executed within the pool constructor
  /// @param tickSpacing The amount of required tick separation, realized in multiples of `tickSpacing`
  ///     e.g., a tickSpacing of 3 requires ticks to be initialized every 3rd tick i.e., ..., -6, -3, 0, 3, 6, ...
  /// @return The max liquidity per tick
  function tickSpacingToMaxLiquidityPerTick(int24 tickSpacing) internal pure returns (uint128) {
    int24 minTick = (TickMath.MIN_TICK / tickSpacing) * tickSpacing;
    int24 maxTick = (TickMath.MAX_TICK / tickSpacing) * tickSpacing;
    uint24 numTicks = uint24((maxTick - minTick) / tickSpacing) + 1;
    return type(uint128).max / numTicks;
  }

  /// @notice Retrieves fee growth data
  /// Ithil: only use it with lower = self[tickLower] and upper = self[tickUpper]
  /// @param lower The info of the lower tick boundary of the position
  /// @param upper The info of the upper tick boundary of the position
  /// @param tickLower The lower tick boundary of the position
  /// @param tickUpper The upper tick boundary of the position
  /// @param tickCurrent The current tick
  /// @param feeGrowthGlobal0X128 The all-time global fee growth, per unit of liquidity, in token0
  /// @param feeGrowthGlobal1X128 The all-time global fee growth, per unit of liquidity, in token1
  /// @return feeGrowthInside0X128 The all-time fee growth in token0, per unit of liquidity, inside the position's tick boundaries
  /// @return feeGrowthInside1X128 The all-time fee growth in token1, per unit of liquidity, inside the position's tick boundaries
  function getFeeGrowthInside(
    Tick.Info memory lower,
    Tick.Info memory upper,
    int24 tickLower,
    int24 tickUpper,
    int24 tickCurrent,
    uint256 feeGrowthGlobal0X128,
    uint256 feeGrowthGlobal1X128
  ) internal pure returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) {
    // calculate fee growth below
    uint256 feeGrowthBelow0X128;
    uint256 feeGrowthBelow1X128;
    if (tickCurrent >= tickLower) {
      feeGrowthBelow0X128 = lower.feeGrowthOutside0X128;
      feeGrowthBelow1X128 = lower.feeGrowthOutside1X128;
    } else {
      feeGrowthBelow0X128 = feeGrowthGlobal0X128 - lower.feeGrowthOutside0X128;
      feeGrowthBelow1X128 = feeGrowthGlobal1X128 - lower.feeGrowthOutside1X128;
    }

    // calculate fee growth above
    uint256 feeGrowthAbove0X128;
    uint256 feeGrowthAbove1X128;
    if (tickCurrent < tickUpper) {
      feeGrowthAbove0X128 = upper.feeGrowthOutside0X128;
      feeGrowthAbove1X128 = upper.feeGrowthOutside1X128;
    } else {
      feeGrowthAbove0X128 = feeGrowthGlobal0X128 - upper.feeGrowthOutside0X128;
      feeGrowthAbove1X128 = feeGrowthGlobal1X128 - upper.feeGrowthOutside1X128;
    }

    feeGrowthInside0X128 = feeGrowthGlobal0X128 - feeGrowthBelow0X128 - feeGrowthAbove0X128;
    feeGrowthInside1X128 = feeGrowthGlobal1X128 - feeGrowthBelow1X128 - feeGrowthAbove1X128;
  }

  /// @notice Updates a tick and returns true if the tick was flipped from initialized to uninitialized, or vice versa
  /// Ithil: always use with info = self[tick]
  /// @param info The info tick that will be updated
  /// @param tick The tick that will be updated
  /// @param tickCurrent The current tick
  /// @param liquidityDelta A new amount of liquidity to be added (subtracted) when tick is crossed from left to right (right to left)
  /// @param feeGrowthGlobal0X128 The all-time global fee growth, per unit of liquidity, in token0
  /// @param feeGrowthGlobal1X128 The all-time global fee growth, per unit of liquidity, in token1
  /// @param secondsPerLiquidityCumulativeX128 The all-time seconds per max(1, liquidity) of the pool
  /// @param tickCumulative The tick * time elapsed since the pool was first initialized
  /// @param time The current block timestamp cast to a uint32
  /// @param upper true for updating a position's upper tick, or false for updating a position's lower tick
  /// @param maxLiquidity The maximum liquidity allocation for a single tick
  /// @return flipped Whether the tick was flipped from initialized to uninitialized, or vice versa
  function update(
    Tick.Info memory info,
    int24 tick,
    int24 tickCurrent,
    int128 liquidityDelta,
    uint256 feeGrowthGlobal0X128,
    uint256 feeGrowthGlobal1X128,
    uint160 secondsPerLiquidityCumulativeX128,
    int56 tickCumulative,
    uint32 time,
    bool upper,
    uint128 maxLiquidity
  ) internal pure returns (bool flipped) {
    uint128 liquidityGrossBefore = info.liquidityGross;
    uint128 liquidityGrossAfter = LiquidityMath.addDelta(liquidityGrossBefore, liquidityDelta);

    require(liquidityGrossAfter <= maxLiquidity, "LO");

    flipped = (liquidityGrossAfter == 0) != (liquidityGrossBefore == 0);

    if (liquidityGrossBefore == 0) {
      // by convention, we assume that all growth before a tick was initialized happened _below_ the tick
      if (tick <= tickCurrent) {
        info.feeGrowthOutside0X128 = feeGrowthGlobal0X128;
        info.feeGrowthOutside1X128 = feeGrowthGlobal1X128;
        info.secondsPerLiquidityOutsideX128 = secondsPerLiquidityCumulativeX128;
        info.tickCumulativeOutside = tickCumulative;
        info.secondsOutside = time;
      }
      info.initialized = true;
    }

    info.liquidityGross = liquidityGrossAfter;

    // when the lower (upper) tick is crossed left to right (right to left), liquidity must be added (removed)
    info.liquidityNet = upper
      ? int256(info.liquidityNet).sub(liquidityDelta).toInt128()
      : int256(info.liquidityNet).add(liquidityDelta).toInt128();
  }

  /// @notice Transitions to next tick as needed by price movement
  /// @param info The result of the mapping containing all tick information for initialized ticks
  /// @param feeGrowthGlobal0X128 The all-time global fee growth, per unit of liquidity, in token0
  /// @param feeGrowthGlobal1X128 The all-time global fee growth, per unit of liquidity, in token1
  /// @param secondsPerLiquidityCumulativeX128 The current seconds per liquidity
  /// @param tickCumulative The tick * time elapsed since the pool was first initialized
  /// @param time The current block.timestamp
  /// @return liquidityNet The amount of liquidity added (subtracted) when tick is crossed from left to right (right to left)
  function cross(
    Tick.Info memory info,
    uint256 feeGrowthGlobal0X128,
    uint256 feeGrowthGlobal1X128,
    uint160 secondsPerLiquidityCumulativeX128,
    int56 tickCumulative,
    uint32 time
  ) internal pure returns (int128 liquidityNet) {
    info.feeGrowthOutside0X128 = feeGrowthGlobal0X128 - info.feeGrowthOutside0X128;
    info.feeGrowthOutside1X128 = feeGrowthGlobal1X128 - info.feeGrowthOutside1X128;
    info.secondsPerLiquidityOutsideX128 = secondsPerLiquidityCumulativeX128 - info.secondsPerLiquidityOutsideX128;
    info.tickCumulativeOutside = tickCumulative - info.tickCumulativeOutside;
    info.secondsOutside = time - info.secondsOutside;
    liquidityNet = info.liquidityNet;
  }
}
