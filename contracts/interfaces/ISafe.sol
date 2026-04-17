// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;

interface ISafe {
  function isOwner(address owner) external view returns (bool);
  function getOwners() external view returns (address[] memory);
}
