//        __  __    __  ________  _______    ______   ________
//       /  |/  |  /  |/        |/       \  /      \ /        |
//   ____$$ |$$ |  $$ |$$$$$$$$/ $$$$$$$  |/$$$$$$  |$$$$$$$$/
//  /    $$ |$$ |__$$ |$$ |__    $$ |  $$ |$$ | _$$/ $$ |__
// /$$$$$$$ |$$    $$ |$$    |   $$ |  $$ |$$ |/    |$$    |
// $$ |  $$ |$$$$$$$$ |$$$$$/    $$ |  $$ |$$ |$$$$ |$$$$$/
// $$ \__$$ |$$ |  $$ |$$ |_____ $$ |__$$ |$$ \__$$ |$$ |_____
// $$    $$ |$$ |  $$ |$$       |$$    $$/ $$    $$/ $$       |
//  $$$$$$$/ $$/   $$/ $$$$$$$$/ $$$$$$$/   $$$$$$/  $$$$$$$$/
//
// dHEDGE DAO - https://dhedge.org
//
// MIT License
// ===========
//
// Copyright (c) 2021 dHEDGE DAO
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//

// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

import "../utils/TxDataUtils.sol";
import "../interfaces/guards/IGuard.sol";
import "../interfaces/IPoolManagerLogic.sol";
import "../interfaces/IHasSupportedAsset.sol";
import "../interfaces/quick/IStakingRewardsFactory.sol";
import "../interfaces/quick/IStakingRewards.sol";

/// @title Transaction guard for Quickswap's Staking Reward contract
contract QuickStakingRewardsGuard is TxDataUtils, IGuard {
  using SafeMathUpgradeable for uint256;

  event Stake(address fundAddress, address asset, address stakingContract, uint256 amount, uint256 time);
  event Unstake(address fundAddress, address asset, address stakingContract, uint256 amount, uint256 time);
  event Claim(address fundAddress, address stakingContract, uint256 time);

  address public rewardToken; // QUICK token

  constructor(address _rewardToken) {
    rewardToken = _rewardToken;
  }

  /// @notice Transaction guard for Sushi MiniChefV2
  /// @dev It supports stake, withdraw, getReward functionalities
  /// @param _poolManagerLogic the pool manager logic
  /// @param to The contract to send transaction to
  /// @param data The transaction data
  /// @return txType the transaction type of a given transaction data. 5 for `Stake` type, 6 for `Unstake`, 7 for `Claim`
  /// @return isPublic if the transaction is public or private
  function txGuard(
    address _poolManagerLogic,
    address to,
    bytes calldata data
  )
    external
    override
    returns (
      uint16 txType, // transaction type
      bool isPublic
    )
  {
    bytes4 method = getMethod(data);
    IPoolManagerLogic poolManagerLogic = IPoolManagerLogic(_poolManagerLogic);
    address poolLogic = poolManagerLogic.poolLogic();

    if (method == bytes4(keccak256("stake(uint256)"))) {
      uint256 amount = uint256(getInput(data, 0)); // Stake token amount.
      address stakingToken = IStakingRewards(to).stakingToken();
      address rewardsToken = IStakingRewards(to).rewardsToken();

      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(stakingToken), "unsupported staking asset");
      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(rewardsToken), "enable reward token");

      emit Stake(poolLogic, stakingToken, to, amount, block.timestamp);

      txType = 5; // `Stake` type
    } else if (method == bytes4(keccak256("withdraw(uint256)"))) {
      uint256 amount = uint256(getInput(data, 0)); // Rewards token amount to be withdrawn.
      address stakingToken = IStakingRewards(to).stakingToken();

      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(stakingToken), "unsupported staking asset");

      emit Unstake(poolLogic, stakingToken, to, amount, block.timestamp);

      txType = 6; // `Unstake` type
    } else if (method == bytes4(keccak256("getReward()"))) {
      address rewardsToken = IStakingRewards(to).rewardsToken();
      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(rewardsToken), "enable reward token");

      emit Claim(poolLogic, to, block.timestamp);

      txType = 7; // `Claim` type
      isPublic = true;
    }
  }
}
