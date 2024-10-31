// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

interface ICompoundV3Comet {
  function supply(address asset, uint256 amount) external;

  function withdraw(address asset, uint256 amount) external;

  function baseToken() external view returns (address);
}
