// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

interface IMutableBalanceAssetGuard {
  function isStateMutatingGuard() external view returns (bool);

  function getBalanceMutable(address pool, address asset) external returns (uint256 balance);
}
