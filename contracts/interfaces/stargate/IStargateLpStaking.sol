// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

interface IStargateLpStaking {
  struct PoolInfo {
    address lpToken; // Address of LP token contract.
    uint256 allocPoint; // How many allocation points assigned to this pool. STGs to distribute per block.
    uint256 lastRewardBlock; // Last block number that STGs distribution occurs.
    uint256 accStargatePerShare; // Accumulated STGs per share, times 1e12. See below.
  }

  struct UserInfo {
    uint256 amount; // How many LP tokens the user has provided.
    uint256 rewardDebt; // Reward debt. See explanation below.
  }

  function deposit(uint256 pid, uint256 amount) external;

  function withdraw(uint256 pid, uint256 amount) external;

  function emergencyWithdraw(uint256 pid) external;

  function poolLength() external view returns (uint256);

  function poolInfo(uint256 poolId) external view returns (PoolInfo memory _poolInfo);

  function userInfo(uint256 poolId, address user) external view returns (UserInfo memory _userInfo);

  function stargate() external view returns (address); // used on the Polygon version

  function eToken() external view returns (address); // used on the Optimism version
}
