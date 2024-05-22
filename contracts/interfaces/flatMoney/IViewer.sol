// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

interface IViewer {
  function getFlatcoinPriceInUSD() external view returns (uint256 priceInUSD);
}
