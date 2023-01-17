//
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
// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import "./IDhedgeStakingV2NFTJson.sol";

interface IDhedgeStakingV2Storage {
  struct Stake {
    uint256 dhtAmount;
    uint256 dhtStakeStartTime;
    address dhedgePoolAddress;
    uint256 dhedgePoolAmount;
    uint256 dhedgePoolStakeStartTime;
    uint256 stakeStartTokenPrice;
    bool unstaked;
    uint256 unstakeTime;
    uint256 reward;
    uint256 claimedReward;
    uint256 rewardParamsEmissionsRate;
    uint256 stakeFinishTokenPrice;
    uint256 vdhtAccruedAtUnstake;
    uint256 dhedgePoolRemainingExitCooldownAtStakeTime;
  }

  struct PoolConfiguration {
    bool configured;
    uint256 stakeCap;
    uint256 stakedSoFar;
  }

  struct RewardParams {
    uint256 stakeDurationDelaySeconds;
    uint256 maxDurationBoostSeconds;
    uint256 maxPerformanceBoostNumerator;
    uint256 maxPerformanceBoostDenominator;
    uint256 stakingRatio;
    uint256 emissionsRate;
    uint256 emissionsRateDenominator;
  }

  /// Only Owner

  /// @notice Allows the owner to allow staking of a pool by setting a cap > 0
  /// @dev can also be used to restrict staking of a pool by setting cap back to 0
  function configurePool(address pool, uint256 cap) external;

  /// @notice Allows the owner to modify the dhtCap which controls the max staking value
  /// @dev can also be used to restrict staking cap back to 0 or rewardedDHT
  function setDHTCap(uint256 newDHTCap) external;

  /// @notice Allows the owner to adjust the maxVDurationTimeSeconds
  /// @param newMaxVDurationTimeSeconds time to reach max VHDT for a staker
  function setMaxVDurationTimeSeconds(uint256 newMaxVDurationTimeSeconds) external;

  /// @notice Allows the owner to adjust the setStakeDurationDelaySeconds
  /// @param newStakeDurationDelaySeconds delay before a staker starts to receive rewards
  function setStakeDurationDelaySeconds(uint256 newStakeDurationDelaySeconds) external;

  /// @notice Allows the owner to adjust the maxDurationBoostSeconds
  /// @param newMaxDurationBoostSeconds time to reach maximum stake duration boost
  function setMaxDurationBoostSeconds(uint256 newMaxDurationBoostSeconds) external;

  /// @notice Allows the owner to adjust the maxPerformanceBoostNumerator
  /// @param newMaxPerformanceBoostNumerator the performance increase to reach max boost
  function setMaxPerformanceBoostNumerator(uint256 newMaxPerformanceBoostNumerator) external;

  /// @notice Allows the owner to adjust the stakingRatio
  /// @param newStakingRatio the amount of dht that can be staked per dollar of DHPT
  function setStakingRatio(uint256 newStakingRatio) external;

  /// @notice Allows the owner to adjust the emissionsRate
  /// @param newEmissionsRate currently 1 not used
  function setEmissionsRate(uint256 newEmissionsRate) external;

  /// @notice Allows the owner to adjust the rewardStreamingTime
  /// @param newRewardStreamingTime max amount of aggregate value of pool tokens that can be staked
  function setRewardStreamingTime(uint256 newRewardStreamingTime) external;

  /// VIEW

  /// @notice The contract address for DHT
  function dhtAddress() external view returns (address);

  /// @notice The total number of pools configured for staking
  /// @dev can be used with poolConfiguredByIndex and poolConfiguration to look up all existing pool configs
  function numberOfPoolsConfigured() external returns (uint256 numberOfPools);

  /// @notice Returns the poolAddress stored at the index
  /// @dev can be used with numberOfPoolsConfigured and poolConfiguration to get all information about configured pools
  /// @param index the index to look up
  /// @return poolAddress the address at the index
  function poolConfiguredByIndex(uint256 index) external returns (address poolAddress);

  /// @notice Allows the owner to set the tokenUriGenerator contract
  /// @param newTokenUriGenerator the address of the deployed tokenUriGenerator
  function setTokenUriGenerator(IDhedgeStakingV2NFTJson newTokenUriGenerator) external;
}
