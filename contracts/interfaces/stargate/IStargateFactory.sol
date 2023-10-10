// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

interface IStargateFactory {
  function getPool(uint256 poolId) external view returns (address);
}
