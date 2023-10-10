// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

interface IPerpsV2MarketSettings {
  function minInitialMargin() external view returns (uint256);

  function minKeeperFee() external view returns (uint256);
}
