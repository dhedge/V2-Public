// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

interface IStakingRewardsFactory {
  function rewardsToken() external view returns(address);

  function stakingRewardsInfoByStakingToken(address stakingToken)
    external
    view
    returns (
      address stakingRewards,
      uint256 rewardAmount,
      uint256 duration
    );
}
