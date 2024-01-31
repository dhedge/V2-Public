// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <=0.8.10;

interface IChainlinkPriceOracle {
  // price in 18 decimals
  function getPrice(address cToken) external view returns (uint256);

  // price is extended for comptroller usage based on decimals of exchangeRate
  function getUnderlyingPrice(address cToken) external view returns (uint256);
}
