// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

interface IHasFeeInfo {
  // Manager fee
  function getMaximumFee() external view returns (uint256, uint256, uint256, uint256, uint256);

  function maximumPerformanceFeeNumeratorChange() external view returns (uint256);

  function performanceFeeNumeratorChangeDelay() external view returns (uint256);

  function getExitCooldown() external view returns (uint256);
}
