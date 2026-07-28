// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;

interface ISyntheticSharesOracle {
  /// @notice Get the synthetic shares multiplier for an Ondo asset
  /// @param asset The Ondo gmToken address
  /// @return sValue The multiplier in 18 decimals
  /// @return paused Whether the asset is paused (e.g. corporate action)
  function getSValue(address asset) external view returns (uint128 sValue, bool paused);
}
