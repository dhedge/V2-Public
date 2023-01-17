// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;

interface IRewardsContract {
  // solhint-disable-next-line func-name-mixedcase
  function reward_count() external view returns (uint256);
}
