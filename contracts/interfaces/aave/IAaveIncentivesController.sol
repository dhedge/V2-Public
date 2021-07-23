// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

interface IAaveIncentivesController {
  function claimRewards(
    address[] calldata assets,
    uint256 amount,
    address to
  ) external;

  function getUserUnclaimedRewards(address user) external view returns (uint256 rewards);
}
