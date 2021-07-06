// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

interface IGovernance {
  function contractGuards(address target) external view returns(address guard);

  function assetGuards(uint8 assetType) external  view returns(address guard);
}