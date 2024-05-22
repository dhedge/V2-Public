// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

interface IVelodromeV2Voter {
  /// @dev Address => Gauge
  function isGauge(address) external view returns (bool);
}
