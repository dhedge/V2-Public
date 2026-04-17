// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

interface IDytmOracleModule {
  function setOracle(address asset, address oracle, uint256 maxStaleness) external;
  function oracles(address asset) external view returns (address oracle, uint256 maxStaleness, uint256 scale);
}
