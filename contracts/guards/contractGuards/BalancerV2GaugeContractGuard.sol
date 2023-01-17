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
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

import "../../utils/TxDataUtils.sol";
import "../../interfaces/IHasAssetInfo.sol";
import "../../interfaces/IPoolLogic.sol";
import "../../interfaces/IPoolManagerLogic.sol";
import "../../interfaces/IHasSupportedAsset.sol";
import "../../interfaces/guards/IGuard.sol";
import "../../interfaces/balancer/IRewardsOnlyGauge.sol";
import "../../interfaces/balancer/IRewardsContract.sol";

/// @title Transaction guard for Balancer V2 Reward Gauge
contract BalancerV2GaugeContractGuard is TxDataUtils, IGuard {
  using SafeMathUpgradeable for uint256;

  event Claim(address fundAddress, address stakingContract, uint256 time);
  event Stake(address fundAddress, address stakingToken, address stakingContract, uint256 amount, uint256 time);
  event Unstake(address fundAddress, address stakingToken, address stakingContract, uint256 amount, uint256 time);

  /// @notice Transaction guard for Balancer V2 Reward Gauge
  /// @dev It supports deposit/withdraw/claim functionalities
  /// @param _poolManagerLogic the pool manager logic
  /// @param to The contract to send transaction to
  /// @param data The transaction data
  /// @return txType the transaction type of a given transaction data. 5 for `Deposit`, 6 for `Withdraw`, 7 for `Claim`
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
    IPoolManagerLogic poolManagerLogic = IPoolManagerLogic(_poolManagerLogic);
    address poolLogic = poolManagerLogic.poolLogic();

    bytes4 method = getMethod(data);
    if (method == bytes4(keccak256("deposit(uint256)"))) {
      uint256 amount = abi.decode(getParams(data), (uint256));

      address lpToken = IRewardsOnlyGauge(to).lp_token();
      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(lpToken), "enable lp token");
      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(to), "enable gauge token");

      checkRewardTokens(to, _poolManagerLogic, poolLogic, false);

      emit Stake(poolLogic, lpToken, to, amount, block.timestamp);

      txType = 5; // `Stake` type
    } else if (method == bytes4(keccak256("deposit(uint256,address)"))) {
      (uint256 amount, address user) = abi.decode(getParams(data), (uint256, address));
      require(poolLogic == user, "user is not pool");

      address lpToken = IRewardsOnlyGauge(to).lp_token();
      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(lpToken), "enable lp token");
      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(to), "enable gauge token");

      checkRewardTokens(to, _poolManagerLogic, poolLogic, false);

      emit Stake(poolLogic, lpToken, to, amount, block.timestamp);

      txType = 5; // `Stake` type
    } else if (method == bytes4(keccak256("deposit(uint256,address,bool)"))) {
      (uint256 amount, address user, ) = abi.decode(getParams(data), (uint256, address, bool));
      require(poolLogic == user, "user is not pool");

      address lpToken = IRewardsOnlyGauge(to).lp_token();
      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(lpToken), "enable lp token");
      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(to), "enable gauge token");

      checkRewardTokens(to, _poolManagerLogic, poolLogic, false);

      emit Stake(poolLogic, lpToken, to, amount, block.timestamp);

      txType = 5; // `Stake` type
    } else if (method == bytes4(keccak256("withdraw(uint256)"))) {
      uint256 amount = abi.decode(getParams(data), (uint256));

      address lpToken = IRewardsOnlyGauge(to).lp_token();
      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(lpToken), "enable lp token");
      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(to), "enable gauge token");

      emit Unstake(poolLogic, lpToken, to, amount, block.timestamp);

      txType = 6; // `Unstake` type
    } else if (method == bytes4(keccak256("withdraw(uint256,bool)"))) {
      (uint256 amount, bool isClaimRewards) = abi.decode(getParams(data), (uint256, bool));

      address lpToken = IRewardsOnlyGauge(to).lp_token();
      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(lpToken), "enable lp token");
      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(to), "enable gauge token");

      if (isClaimRewards) {
        checkRewardTokens(to, _poolManagerLogic, poolLogic, false);
      }

      emit Unstake(poolLogic, lpToken, to, amount, block.timestamp);

      txType = 6; // `Unstake` type
    } else if (method == bytes4(keccak256("claim_rewards()"))) {
      checkRewardTokens(to, _poolManagerLogic, poolLogic, true);

      emit Claim(poolLogic, to, block.timestamp);

      txType = 7; // `Claim` type
      isPublic = true;
    } else if (method == bytes4(keccak256("claim_rewards(address)"))) {
      address user = abi.decode(getParams(data), (address));

      require(poolLogic == user, "user is not pool");

      checkRewardTokens(to, _poolManagerLogic, poolLogic, true);

      emit Claim(poolLogic, to, block.timestamp);

      txType = 7; // `Claim` type
      isPublic = true;
    } else if (method == bytes4(keccak256("claim_rewards(address,address)"))) {
      (address user, address receiver) = abi.decode(getParams(data), (address, address));

      require(poolLogic == user, "user is not pool");
      require(poolLogic == receiver, "receiver is not pool");

      checkRewardTokens(to, _poolManagerLogic, poolLogic, true);

      emit Claim(poolLogic, to, block.timestamp);

      txType = 7; // `Claim` type
      isPublic = true;
    }
  }

  function checkRewardTokens(
    address gaugeAddress,
    address poolManagerLogic,
    address poolLogic,
    bool checkClaimableAmount
  ) internal view {
    IRewardsOnlyGauge gauge = IRewardsOnlyGauge(gaugeAddress);
    address factory = IPoolLogic(poolLogic).factory();
    uint256 rewardCount = IRewardsContract(gauge.reward_contract()).reward_count();
    for (uint256 i = 0; i < rewardCount; i++) {
      address rewardToken = gauge.reward_tokens(i);
      if ((!checkClaimableAmount || gauge.claimable_reward(poolLogic, rewardToken) > 0)) {
        require(
          !IHasAssetInfo(factory).isValidAsset(rewardToken) ||
            IHasSupportedAsset(poolManagerLogic).isSupportedAsset(rewardToken),
          "enable reward token"
        );
      }
    }
  }
}
