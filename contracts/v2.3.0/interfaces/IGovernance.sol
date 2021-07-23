// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

interface IGovernanceV23 {
  function contractGuards(address target) external view returns (address guard);

  function assetGuards(uint16 assetType) external view returns (address guard);
}
