// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

interface IAToken {
  function POOL() external view returns (address);

  function balanceOf(address owner) external view returns (uint256);

  function scaledBalanceOf(address user) external view returns (uint256);
}
