// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.7.6;

/// @title The interface for a CL Pool
/// @notice A CL pool facilitates swapping and automated market making between any two assets that strictly conform
/// to the ERC20 specification
interface IVelodromeCLPool {
  function slot0()
    external
    view
    returns (
      uint160 sqrtPriceX96,
      int24 tick,
      uint16 observationIndex,
      uint16 observationCardinality,
      uint16 observationCardinalityNext,
      bool unlocked
    );

  /// @notice The gauge corresponding to this pool
  /// @return The gauge contract address
  function gauge() external view returns (address);

  function ticks(
    int24 tick
  )
    external
    view
    returns (
      uint128 liquidityGross,
      int128 liquidityNet,
      int128 stakedLiquidityNet,
      uint256 feeGrowthOutside0X128,
      uint256 feeGrowthOutside1X128,
      uint256 rewardGrowthOutsideX128,
      int56 tickCumulativeOutside,
      uint160 secondsPerLiquidityOutsideX128,
      uint32 secondsOutside,
      bool initialized
    );
  function feeGrowthGlobal0X128() external view returns (uint256);
  function feeGrowthGlobal1X128() external view returns (uint256);
  function observe(
    uint32[] calldata secondsAgos
  ) external view returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s);
  function observations(
    uint256 index
  )
    external
    view
    returns (uint32 blockTimestamp, int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128, bool initialized);
  function liquidity() external view returns (uint128);
  function token0() external view returns (address);
  function token1() external view returns (address);
}
