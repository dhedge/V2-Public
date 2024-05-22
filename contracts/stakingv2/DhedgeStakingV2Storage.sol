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
pragma abicoder v2;

import "./interfaces/IDhedgeStakingV2.sol";
import "./interfaces/IDhedgeStakingV2NFTJson.sol";

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract DhedgeStakingV2Storage is IDhedgeStakingV2Storage, OwnableUpgradeable {
  using CountersUpgradeable for CountersUpgradeable.Counter;
  using SafeMath for uint256;

  event OwnerOperation(string operation);

  // Address of DHT contract
  address public override dhtAddress;

  // Total amount of pools stored in poolConfiguration
  uint256 public override numberOfPoolsConfigured;
  // Allows the lookup of address by index
  mapping(uint256 => address) public override poolConfiguredByIndex;
  // Pool Configuration by pool address
  mapping(address => IDhedgeStakingV2Storage.PoolConfiguration) internal poolConfiguration;

  // tokenId -> Stake
  mapping(uint256 => IDhedgeStakingV2Storage.Stake) public stakes;

  CountersUpgradeable.Counter internal _tokenIdCounter;

  // The amount of value of dhedge pool tokens that have been staked so far
  uint256 public totalStakingValue;
  // The amount of dhtRewarded so far
  uint256 public dhtRewarded;

  // Failsafe to ensure we don't eat into staked dht when distributing rewards
  uint256 public dhtStaked;
  uint256 public aggregateStakeStartTime;

  /// OWNER EDITABLE

  // Max amount of dht emissions
  uint256 public dhtCap;
  // How long before reaching maximum vDHT
  uint256 public maxVDurationTimeSeconds;
  // How long rewards for a staked take to fully stream to a user
  uint256 public rewardStreamingTime;
  // Parameters for calculating rewards
  RewardParams public rewardParams;
  // The contract that contains the code for generating the tokenURI
  IDhedgeStakingV2NFTJson public tokenUriGenerator;

  uint256[50] private __gap;

  /// @notice Allows the owner to adjust the maxVDurationTimeSeconds
  /// @param newMaxVDurationTimeSeconds time to reach max VHDT for a staker
  function setMaxVDurationTimeSeconds(uint256 newMaxVDurationTimeSeconds) external override onlyOwner {
    require(newMaxVDurationTimeSeconds > 30 days, "Must be more than 30 days");
    require(newMaxVDurationTimeSeconds < 730 days, "Must be less than 2 years");
    maxVDurationTimeSeconds = newMaxVDurationTimeSeconds;
    emit OwnerOperation("setMaxVDurationTimeSeconds");
  }

  /// @notice Allows the owner to adjust the setStakeDurationDelaySeconds
  /// @param newStakeDurationDelaySeconds delay before a staker starts to receive rewards
  function setStakeDurationDelaySeconds(uint256 newStakeDurationDelaySeconds) external override onlyOwner {
    require(newStakeDurationDelaySeconds < 90 days, "Must be less than 90 days");
    rewardParams.stakeDurationDelaySeconds = newStakeDurationDelaySeconds;
    emit OwnerOperation("setStakeDurationDelaySeconds");
  }

  /// @notice Allows the owner to adjust the maxDurationBoostSeconds
  /// @param newMaxDurationBoostSeconds time to reach maximum stake duration boost
  function setMaxDurationBoostSeconds(uint256 newMaxDurationBoostSeconds) external override onlyOwner {
    require(newMaxDurationBoostSeconds > 30 days, "Must be more than 30 days");
    require(newMaxDurationBoostSeconds < 730 days, "Must be less than 2 years");
    rewardParams.maxDurationBoostSeconds = newMaxDurationBoostSeconds;
    emit OwnerOperation("setMaxDurationBoostSeconds");
  }

  /// @notice Allows the owner to adjust the maxPerformanceBoostNumerator
  /// @param newMaxPerformanceBoostNumerator the performance increase to reach max boost
  function setMaxPerformanceBoostNumerator(uint256 newMaxPerformanceBoostNumerator) external override onlyOwner {
    require(newMaxPerformanceBoostNumerator > 100, "Must be more than 10%");
    require(newMaxPerformanceBoostNumerator < 2000, "Must be less than 200%");
    rewardParams.maxPerformanceBoostNumerator = newMaxPerformanceBoostNumerator;
    emit OwnerOperation("setMaxPerformanceBoostNumerator");
  }

  /// @notice Allows the owner to adjust the stakingRatio
  /// @param newStakingRatio the amount of dht that can be staked per dollar of DHPT
  function setStakingRatio(uint256 newStakingRatio) external override onlyOwner {
    require(newStakingRatio > 0, "Must be greater than 0");
    require(newStakingRatio < 20, "Must be less than 20");
    rewardParams.stakingRatio = newStakingRatio;
    emit OwnerOperation("setStakingRatio");
  }

  /// @notice Allows the owner to adjust the emissionsRate
  /// @param newEmissionsRate the current emissions rate
  function setEmissionsRate(uint256 newEmissionsRate) external override onlyOwner {
    require(newEmissionsRate <= 3000, "Must be lower than 300%");
    rewardParams.emissionsRate = newEmissionsRate;
    emit OwnerOperation("setEmissionsRate");
  }

  /// @notice Allows the owner to adjust the dhtCap
  /// @dev to disable new staking set to 0
  /// @param newDHTCap max amount of aggregate value of pool tokens that can be staked
  function setDHTCap(uint256 newDHTCap) external override onlyOwner {
    require(newDHTCap <= 7_000_000 * 10 ** 18, "Must be lower than 7 million dht");
    dhtCap = newDHTCap;
    emit OwnerOperation("setDHTCap");
  }

  /// @notice Allows the owner to adjust the rewardStreamingTime
  /// @param newRewardStreamingTime max amount of aggregate value of pool tokens that can be staked
  function setRewardStreamingTime(uint256 newRewardStreamingTime) external override onlyOwner {
    require(newRewardStreamingTime > 0, "Must be greater than 0");
    require(newRewardStreamingTime < 30 days, "Must be less than 30 days");
    rewardStreamingTime = newRewardStreamingTime;
    emit OwnerOperation("setRewardStreamingTime");
  }

  /// @notice Allows configuring a pool for staking
  /// @dev can get all pools by for(n of numberOfPoolsConfigured) poolConfiguration[allPoolsConfigured[n]].stakeCap != 0
  /// @dev to disable a pool set cap == 0
  /// @param pool the dhedge pool address
  /// @param cap The max amount of value in pooltokens that can be staked for this pool
  function configurePool(address pool, uint256 cap) external override onlyOwner {
    require(pool != address(0), "Pool cannot be address(0)");
    IDhedgeStakingV2Storage.PoolConfiguration storage pc = poolConfiguration[pool];

    if (!pc.configured) {
      pc.configured = true;
      poolConfiguredByIndex[numberOfPoolsConfigured] = pool;
      numberOfPoolsConfigured = numberOfPoolsConfigured.add(1);
    }

    pc.stakeCap = cap;
    emit OwnerOperation("configurePool");
  }

  /// @notice Allows the owner to set the tokenUriGenerator contract
  /// @param newTokenUriGenerator the address of the deployed tokenUriGenerator
  function setTokenUriGenerator(IDhedgeStakingV2NFTJson newTokenUriGenerator) external override onlyOwner {
    require(address(newTokenUriGenerator) != address(0), "Cannot be address(0)");
    tokenUriGenerator = newTokenUriGenerator;
    emit OwnerOperation("setTokenUriGenerator");
  }
}
