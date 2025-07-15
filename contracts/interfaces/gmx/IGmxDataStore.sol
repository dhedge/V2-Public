// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

interface IGmxDataStore {
  function getUint(bytes32 _key) external view returns (uint256 value_);

  function getBytes32ValuesAt(
    bytes32 _setKey,
    uint256 _start,
    uint256 _end
  ) external view returns (bytes32[] memory values_);

  function getBytes32Count(bytes32 setKey) external view returns (uint256);

  function getAddress(bytes32 key) external view returns (address);

  function roleStore() external view returns (address);
  function setUint(bytes32 key, uint256 value) external returns (uint256);
}
