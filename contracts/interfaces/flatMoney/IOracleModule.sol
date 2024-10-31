// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

interface IOracleModule {
  function getPrice() external view returns (uint256 price, uint256 timestamp);

  function getPrice(uint32 maxAge, bool priceDiffCheck) external view returns (uint256 price, uint256 timestamp);
}
