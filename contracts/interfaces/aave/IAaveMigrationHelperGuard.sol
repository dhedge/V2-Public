// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

interface IAaveMigrationHelperGuard {
  function dHedgeVaultsWhitelist(address _poolLogic) external view returns (bool);
}
