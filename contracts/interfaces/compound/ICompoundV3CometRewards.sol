// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

interface ICompoundV3CometRewards {
  struct RewardConfig {
    address token;
    uint64 rescaleFactor;
    bool shouldUpscale;
    uint256 multiplier;
  }
  function rewardConfig(address comet) external view returns (RewardConfig memory);

  function claim(address comet, address receiver, bool shouldAccrue) external;
}
