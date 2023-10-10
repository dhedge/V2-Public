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

import "../ERC20Guard.sol";
import "../../../interfaces/velodrome/IVelodromePair.sol";
import "../../../interfaces/velodrome/IVelodromeGauge.sol";
import "../../../interfaces/velodrome/IVelodromeVoter.sol";
import "../../../interfaces/IHasAssetInfo.sol";
import "../../../interfaces/IPoolLogic.sol";

/// @title Velodrome LP token asset guard
/// @dev Asset type = 15
contract VelodromeLPAssetGuard is ERC20Guard {
  using SafeMathUpgradeable for uint256;

  IVelodromeVoter public voter;

  constructor(address _voter) {
    voter = IVelodromeVoter(_voter);
  }

  /// @notice Creates transaction data for withdrawing Velodrome LP tokens
  /// @dev The same interface can be used for other types of stakeable tokens
  /// @param pool Pool address
  /// @param asset Velodrome LP asset
  /// @param portion The fraction of total Velodrome LP asset to withdraw
  /// @param to The investor address to withdraw to
  /// @return withdrawAsset and
  /// @return withdrawBalance are used to withdraw portion of asset balance to investor
  /// @return transactions is used to execute the Velodrome LP withdrawal transaction in PoolLogic
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
    withdrawAsset = asset;
    withdrawBalance = IERC20(asset).balanceOf(pool).mul(portion).div(10**18);

    IVelodromeGauge gauge = IVelodromeGauge(voter.gauges(asset));
    uint256 rewardsListLength = address(gauge) == address(0) ? 0 : gauge.rewardsListLength();

    uint256 txCount = 0;
    transactions = new MultiTransaction[](5 + rewardsListLength);

    // up-to 3 transactions for LP withdraw processing
    {
      uint256 feeAmount0 = IVelodromePair(asset).claimable0(pool);
      uint256 feeAmount1 = IVelodromePair(asset).claimable1(pool);
      if (feeAmount0 > 0 || feeAmount1 > 0) {
        transactions[txCount].to = asset;
        transactions[txCount].txData = abi.encodeWithSelector(bytes4(keccak256("claimFees()")));
        txCount = txCount.add(1);

        // withdraw claimable fees directly to the user
        if (feeAmount0 > 0) {
          transactions[txCount].to = IVelodromePair(asset).token0();
          transactions[txCount].txData = abi.encodeWithSelector(
            bytes4(keccak256("transfer(address,uint256)")),
            to,
            feeAmount0.mul(portion).div(10**18)
          );
          txCount = txCount.add(1);
        }
        if (feeAmount1 > 0) {
          transactions[txCount].to = IVelodromePair(asset).token1();
          transactions[txCount].txData = abi.encodeWithSelector(
            bytes4(keccak256("transfer(address,uint256)")),
            to,
            feeAmount1.mul(portion).div(10**18)
          );
          txCount = txCount.add(1);
        }
      }
    }

    // up-to 2 + rewardsListLength transactions for gauge withdraw processing
    if (address(gauge) != address(0)) {
      {
        // include to gauge withdraw transaction
        uint256 gaugeLpBalance = gauge.balanceOf(pool);
        if (gaugeLpBalance > 0) {
          uint256 portionBalance = gaugeLpBalance.mul(portion).div(10**18);

          transactions[txCount].to = address(gauge);
          transactions[txCount].txData = abi.encodeWithSelector(bytes4(keccak256("withdraw(uint256)")), portionBalance);
          txCount = txCount.add(1);
        }
      }

      {
        // include gauge reward claim transaction
        address[] memory rewardTokens = new address[](rewardsListLength);
        for (uint256 i = 0; i < rewardsListLength; i++) {
          rewardTokens[i] = gauge.rewards(i);
        }

        transactions[txCount].to = address(gauge);
        transactions[txCount].txData = abi.encodeWithSelector(
          bytes4(keccak256("getReward(address,address[])")),
          pool,
          rewardTokens
        );
        txCount = txCount.add(1);

        // withdraw gauge rewards directly to the user
        for (uint256 i = 0; i < rewardsListLength; i++) {
          uint256 rewardAmount = gauge.earned(rewardTokens[i], pool);
          if (rewardAmount > 0) {
            transactions[txCount].to = rewardTokens[i];
            transactions[txCount].txData = abi.encodeWithSelector(
              bytes4(keccak256("transfer(address,uint256)")),
              to,
              rewardAmount.mul(portion).div(10**18)
            );
            txCount = txCount.add(1);
          }
        }
      }
    }

    // Remove empty items from array
    uint256 reduceLength = (transactions.length).sub(txCount);
    assembly {
      mstore(transactions, sub(mload(transactions), reduceLength))
    }
  }

  function _assetValue(
    address factory,
    address poolManager,
    address token,
    uint256 amount
  ) internal view returns (uint256) {
    if (IHasAssetInfo(factory).isValidAsset(token) && amount > 0) {
      return IPoolManagerLogic(poolManager).assetValue(token, amount);
    } else {
      return 0;
    }
  }

  /// @notice Returns the balance of the managed asset
  /// @dev May include claimable fees & gauge lp/rewards
  /// @param pool address of the pool
  /// @param asset address of the asset
  /// @return balance The asset balance of given pool in lp price
  function getBalance(address pool, address asset) public view override returns (uint256 balance) {
    IVelodromeGauge gauge = IVelodromeGauge(voter.gauges(asset));

    // include lp balances
    balance = IERC20(asset).balanceOf(pool);
    if (address(gauge) != address(0)) {
      balance = balance.add(gauge.balanceOf(pool));
    }

    uint256 rewardsValue; // 18 decimals
    // include fee balance
    address factory = IPoolLogic(pool).factory();
    address poolManagerLogic = IPoolLogic(pool).poolManagerLogic();
    {
      address token0 = IVelodromePair(asset).token0();
      uint256 feeAmount0 = IVelodromePair(asset).claimable0(pool);
      rewardsValue = rewardsValue.add(_assetValue(factory, poolManagerLogic, token0, feeAmount0)); // 18 decimals
    }
    {
      address token1 = IVelodromePair(asset).token1();
      uint256 feeAmount1 = IVelodromePair(asset).claimable1(pool);
      rewardsValue = rewardsValue.add(_assetValue(factory, poolManagerLogic, token1, feeAmount1)); // 18 decimals
    }

    // include gauge rewards
    if (address(gauge) != address(0)) {
      uint256 rewardsListLength = gauge.rewardsListLength();
      for (uint256 i = 0; i < rewardsListLength; i++) {
        address rewardToken = gauge.rewards(i);
        uint256 rewardAmount = gauge.earned(rewardToken, pool);
        rewardsValue = rewardsValue.add(_assetValue(factory, poolManagerLogic, rewardToken, rewardAmount)); // 18 decimals
      }
    }

    // convert rewards value in lp price
    balance = balance.add(rewardsValue.mul(10**18).div(IHasAssetInfo(factory).getAssetPrice(asset)));
  }
}
