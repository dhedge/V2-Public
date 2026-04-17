// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;

interface IDhedgeNftTrackerStorage {
  function poolFactory() external view returns (address);

  function getAllUintIds(bytes32 _nftType, address _pool) external view returns (uint256[] memory);

  function addUintId(
    address _guardedContract,
    bytes32 _nftType,
    address _pool,
    uint256 _nftID,
    uint256 _maxPositions
  ) external;

  function removeUintId(address _guardedContract, bytes32 _nftType, address _pool, uint256 _nftID) external;

  function getDataCount(bytes32 _nftType, address _pool) external view returns (uint256);
}
