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

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

import "./ERC20Guard.sol";
import "../../interfaces/IERC20Extended.sol";
import "../../interfaces/IPoolLogic.sol";
import "../../interfaces/IHasAssetInfo.sol";
import "../../interfaces/balancer/IRewardsOnlyGauge.sol";
import "../../interfaces/balancer/IRewardsContract.sol";

/// @title Balancer V2 Gauge asset guard
/// @dev Asset type = 10
contract BalancerV2GaugeAssetGuard is ERC20Guard {
  using SafeMathUpgradeable for uint256;

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
    address to
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
    uint256 totalAssetBalance = IERC20Extended(asset).balanceOf(pool);
    uint256 burnAmount = totalAssetBalance.mul(portion).div(10**18);

    if (burnAmount > 0) {
      transactions = new MultiTransaction[](2);

      // withdraw gauge asset (set claim flag true to claim rewards)
      transactions[0].to = asset;
      transactions[0].txData = abi.encodeWithSelector(bytes4(keccak256("withdraw(uint256,bool)")), burnAmount, true);

      // transfer withdrawn lp to user
      transactions[1].to = IRewardsOnlyGauge(asset).lp_token();
      transactions[1].txData = abi.encodeWithSelector(
        IERC20.transfer.selector,
        to, // recipient
        burnAmount
      );
    }

    return (withdrawAsset, withdrawBalance, transactions);
  }

  /// @notice Returns the balance of the managed asset
  /// @dev May include any external balance in staking contracts
  /// @param pool address of the pool
  /// @param asset address of the asset
  /// @return balance The asset balance of given pool
  function getBalance(address pool, address asset) public view override returns (uint256 balance) {
    address factory = IPoolLogic(pool).factory();
    address poolManager = IPoolLogic(pool).poolManagerLogic();

    IRewardsOnlyGauge gauge = IRewardsOnlyGauge(asset);
    address lpToken = gauge.lp_token();

    balance = _assetValue(factory, poolManager, lpToken, gauge.balanceOf(pool));

    uint256 rewardCount = IRewardsContract(gauge.reward_contract()).reward_count();
    for (uint256 i = 0; i < rewardCount; i++) {
      address rewardToken = gauge.reward_tokens(i);
      uint256 rewardBalance = gauge.claimable_reward(pool, rewardToken);
      balance = balance.add(_assetValue(factory, poolManager, rewardToken, rewardBalance));
    }
  }

  function _assetValue(
    address factory,
    address poolManager,
    address token,
    uint256 amount
  ) internal view returns (uint256) {
    if (IHasAssetInfo(factory).isValidAsset(token)) {
      return IPoolManagerLogic(poolManager).assetValue(token, amount);
    } else {
      return 0;
    }
  }
}
