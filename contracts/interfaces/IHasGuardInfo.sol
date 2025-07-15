// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

interface IHasGuardInfo {
  // Get guard
  function getContractGuard(address extContract) external view returns (address);

  // Get asset guard
  function getAssetGuard(address extContract) external view returns (address);
}
