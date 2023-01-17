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
pragma experimental ABIEncoderV2;

import "./ERC20Guard.sol";
import "../../interfaces/quick/IStakingRewardsFactory.sol";
import "../../interfaces/quick/IStakingRewards.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

/// @title Quick LP token asset guard
/// @dev Asset type = 5
contract QuickLPAssetGuard is ERC20Guard, Ownable {
  using SafeMathUpgradeable for uint256;

  IStakingRewardsFactory public stakingRewardsFactory;

  /// @notice Initialise for the contract
  /// @param _stakingRewardsFactory Quickswap's staking rewards factory contract
  constructor(address _stakingRewardsFactory) Ownable() {
    // solhint-disable-next-line reason-string
    require(_stakingRewardsFactory != address(0), "_stakingRewardsFactory address cannot be 0");
    stakingRewardsFactory = IStakingRewardsFactory(_stakingRewardsFactory);
  }

  /// @notice Creates transaction data for withdrawing staked tokens
  /// @dev The same interface can be used for other types of stakeable tokens
  /// @param pool Pool address
  /// @param asset Staked asset
  /// @param portion The fraction of total staked asset to withdraw
  /// @return withdrawAsset and
  /// @return withdrawBalance are used to withdraw portion of asset balance to investor
  /// @return transactions is used to execute the staked withdrawal transaction in PoolLogic
  function withdrawProcessing(
    address pool,
    address asset,
    uint256 portion,
    address // to
  )
    external
    view
    virtual
    override
    returns (
      address withdrawAsset,
      uint256 withdrawBalance,
      MultiTransaction[] memory transactions
    )
  {
    withdrawAsset = asset;
    uint256 totalAssetBalance = IERC20(asset).balanceOf(pool);
    withdrawBalance = totalAssetBalance.mul(portion).div(10**18);

    (address stakingRewards, , ) = stakingRewardsFactory.stakingRewardsInfoByStakingToken(asset);
    uint256 stakedBalance = IStakingRewards(stakingRewards).balanceOf(pool);

    // If there is a staked balance in Quickswap's staking rewards contract
    // Then create the withdrawal transaction data to be executed by PoolLogic
    if (stakedBalance > 0) {
      uint256 unstakeAmount = stakedBalance.mul(portion).div(10**18);
      if (unstakeAmount > 0) {
        transactions = new MultiTransaction[](1);

        // Unstake Quickswap LP
        transactions[0].to = stakingRewards;
        transactions[0].txData = abi.encodeWithSelector(bytes4(keccak256("withdraw(uint256)")), unstakeAmount);

        // Add unstaked lp to withdraw balance
        withdrawBalance = withdrawBalance.add(unstakeAmount);
      }
    }
  }

  /// @notice Returns the balance of the managed asset
  /// @dev May include any external balance in staking contracts
  /// @param pool address of the pool
  /// @param asset address of the asset
  /// @return balance The asset balance of given pool
  function getBalance(address pool, address asset) public view override returns (uint256 balance) {
    (address stakingRewards, , ) = stakingRewardsFactory.stakingRewardsInfoByStakingToken(asset);
    uint256 stakedBalance = IStakingRewards(stakingRewards).balanceOf(pool);
    uint256 poolBalance = IERC20(asset).balanceOf(pool);
    balance = stakedBalance.add(poolBalance);
  }
}
