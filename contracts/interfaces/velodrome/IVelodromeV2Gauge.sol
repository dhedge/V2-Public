// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

interface IVelodromeV2Gauge {
  function balanceOf(address user) external view returns (uint256);

  function rewardPerToken() external view returns (uint256 _rewardPerToken);

  /// @notice Returns the last time the reward was modified or periodFinish if the reward has ended
  function lastTimeRewardApplicable() external view returns (uint256 _time);

  /// @notice Returns accrued balance to date from last claim / first deposit.
  function earned(address _account) external view returns (uint256 _earned);

  function left() external view returns (uint256 _left);

  /// @notice Returns if gauge is linked to a legitimate Velodrome pool
  function isPool() external view returns (bool _isPool);

  function stakingToken() external view returns (address _pool);

  function rewardToken() external view returns (address _token);

  /// @notice Retrieve rewards for an address.
  /// @dev Throws if not called by same address or voter.
  /// @param _account .
  function getReward(address _account) external;

  /// @notice Deposit LP tokens into gauge for msg.sender
  /// @param _amount .
  function deposit(uint256 _amount) external;

  /// @notice Deposit LP tokens into gauge for any user
  /// @param _amount .
  /// @param _recipient Recipient to give balance to
  function deposit(uint256 _amount, address _recipient) external;

  /// @notice Withdraw LP tokens for user
  /// @param _amount .
  function withdraw(uint256 _amount) external;

  /// @dev Notifies gauge of gauge rewards. Assumes gauge reward tokens is 18 decimals.
  ///      If not 18 decimals, rewardRate may have rounding issues.
  function notifyRewardAmount(uint256 amount) external;
}
