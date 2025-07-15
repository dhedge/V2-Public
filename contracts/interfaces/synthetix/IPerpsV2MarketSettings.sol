// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

interface IPerpsV2MarketSettings {
  function minInitialMargin() external view returns (uint256);

  function minKeeperFee() external view returns (uint256);

  function owner() external view returns (address);

  function setOffchainDelayedOrderMaxAge(bytes32 _marketKey, uint256 _offchainDelayedOrderMaxAge) external;
}
