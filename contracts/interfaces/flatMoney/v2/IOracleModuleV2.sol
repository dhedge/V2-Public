// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

interface IOracleModuleV2 {
  function getPrice(address asset) external view returns (uint256 price, uint256 timestamp);
}
