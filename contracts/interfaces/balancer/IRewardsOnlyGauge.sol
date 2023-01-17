// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;

interface IRewardsOnlyGauge {
  // solhint-disable-next-line func-name-mixedcase
  function lp_token() external view returns (address);

  // solhint-disable-next-line func-name-mixedcase
  function reward_tokens(uint256 index) external view returns (address);

  // solhint-disable-next-line func-name-mixedcase
  function reward_contract() external view returns (address);

  // solhint-disable-next-line func-name-mixedcase
  function balanceOf(address user) external view returns (uint256);

  // solhint-disable-next-line func-name-mixedcase
  function claimable_reward(address user, address rewardToken) external view returns (uint256);

  // solhint-disable-next-line func-name-mixedcase
  function claimable_reward_write(address user, address rewardToken) external returns (uint256);

  // solhint-disable-next-line func-name-mixedcase
  function claim_rewards() external;

  // solhint-disable-next-line func-name-mixedcase
  function claim_rewards(address user) external;

  // solhint-disable-next-line func-name-mixedcase
  function claim_rewards(address user, address receiver) external;

  function deposit(uint256 amount) external;

  function deposit(uint256 amount, address user) external;

  function deposit(
    uint256 amount,
    address onBehalf,
    bool isClaimRewards
  ) external;

  function withdraw(uint256 amount) external;

  function withdraw(uint256 amount, bool isClaimRewards) external;
}
