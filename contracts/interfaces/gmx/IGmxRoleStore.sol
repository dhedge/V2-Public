// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

interface IGmxRoleStore {
  function hasRole(address account, bytes32 roleKey) external view returns (bool);
  function getRoleMembers(bytes32 roleKey, uint256 start, uint256 end) external view returns (address[] memory);
}
