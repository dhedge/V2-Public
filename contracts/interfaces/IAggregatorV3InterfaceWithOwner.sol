// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "./IAggregatorV3Interface.sol";

interface IAggregatorV3InterfaceWithOwner is IAggregatorV3Interface {
  function owner() external view returns (address);

  function proposeAggregator(address _aggregator) external;

  function confirmAggregator(address _aggregator) external;

  function aggregator() external view returns (address);
}
