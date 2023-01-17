// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

interface IShortCollateral {
  function settleOptions(uint256[] memory positionIds) external;
}
