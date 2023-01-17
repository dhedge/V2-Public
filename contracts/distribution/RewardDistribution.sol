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
// Copyright (c) 2022 dHEDGE DAO
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

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import "./RewardsAPYCalculator.sol";
import "../interfaces/IHasSupportedAsset.sol";
import "../interfaces/IPoolLogic.sol";
import "../interfaces/IPoolManagerLogic.sol";

contract RewardDistribution is Ownable, Pausable {
  using SafeERC20 for IERC20;
  using SafeMath for uint256;

  struct RewardSummary {
    address pool;
    uint256 amount;
  }

  event RewardsDistribution(RewardSummary[] distributedRewards, uint256 totalDistributedRewards);
  event OwnerOperation(string operation);

  IERC20 public rewardToken;

  address[] public whitelistedPools;

  uint256 public lastDistributionTime;

  uint256 public rewardAmountPerSecond;

  /// @notice Contract starts accruing rewards right after deployment
  /// @dev Can do test deployment first with reward token of no value.
  /// @param _rewardToken ERC20 compliant token address.
  /// @param _rewardAmountPerSecond Mind precision of token from 1st param.
  constructor(address _rewardToken, uint256 _rewardAmountPerSecond) Ownable() Pausable() {
    require(_rewardToken != address(0), "invalid token");
    rewardToken = IERC20(_rewardToken);
    rewardAmountPerSecond = _rewardAmountPerSecond;
    lastDistributionTime = block.timestamp;
  }

  /** Owner Setters */

  /// @notice Setter to change reward token. Mind token precision, resetting rewardAmountPerSecond most likely will be needed
  /// @param _rewardToken ERC20 compliant token address
  function setRewardToken(address _rewardToken) external onlyOwner {
    require(_rewardToken != address(0), "invalid token");
    rewardToken = IERC20(_rewardToken);
    emit OwnerOperation("setRewardToken");
  }

  /// @notice Setter to change amount of reward token streamed per second
  /// @param _rewardAmountPerSecond Mind reward token precision
  function setRewardAmountPerSecond(uint256 _rewardAmountPerSecond) external onlyOwner {
    rewardAmountPerSecond = _rewardAmountPerSecond;
    emit OwnerOperation("setRewardAmountPerSecond");
  }

  /// @notice Setter to change whitelisted for distribution pools
  /// @param _whitelistedPools Setting empty list will stop future distributions
  function setWhitelistedPools(address[] calldata _whitelistedPools) external onlyOwner {
    whitelistedPools = _whitelistedPools;
    emit OwnerOperation("setWhitelistedPools");
  }

  /** View functions */

  /// @notice Getter for pools whitelisted for rewards
  /// @return List of whitelisted pools' addresses
  function getWhitelistedPools() public view returns (address[] memory) {
    return whitelistedPools;
  }

  /// @notice Getter for pools eligible for rewards
  /// @dev Pool considered not eligible if it doesn't have reward token enabled
  /// @return List of eligible pools' addresses
  function getEligiblePools() public view returns (address[] memory) {
    uint256 poolsCount = whitelistedPools.length;
    address[] memory eligiblePools = new address[](poolsCount);
    uint256 index = 0;
    for (uint256 i = 0; i < poolsCount; i++) {
      if (
        IHasSupportedAsset(IPoolLogic(whitelistedPools[i]).poolManagerLogic()).isSupportedAsset(address(rewardToken))
      ) {
        eligiblePools[index] = whitelistedPools[i];
        index++;
      }
    }
    // Reduce length for eligiblePools to remove empty items
    uint256 reducedLength = poolsCount.sub(index);
    assembly {
      mstore(eligiblePools, sub(mload(eligiblePools), reducedLength))
    }
    return eligiblePools;
  }

  /// @notice Aggregates total usd value of all eligible pools
  /// @return tvl Total value in usd
  /// @return eligiblePools List of eligible pools' addresses
  function getEligiblePoolsWithTvl() public view returns (uint256 tvl, address[] memory eligiblePools) {
    eligiblePools = getEligiblePools();
    for (uint256 i = 0; i < eligiblePools.length; i++) {
      tvl += IPoolManagerLogic(IPoolLogic(eligiblePools[i]).poolManagerLogic()).totalFundValue();
    }
  }

  /// @notice Utility function to calculate total amount of rewards ready for distribution at a specific time
  /// @dev Pure function for easier testing
  /// @param _rewardAmountPerSecond Amount of reward token streamed per second
  /// @param _lastDistributionTime Unix timestamp when last distribution happened
  /// @param _blockTimestamp Specific time, must be greater than last distribution time
  /// @return totalRewardsForPeriod Total reward token amount ready for distribution for passed period
  function calculateTotalRewardsForPeriod(
    uint256 _rewardAmountPerSecond,
    uint256 _lastDistributionTime,
    uint256 _blockTimestamp
  ) public pure returns (uint256 totalRewardsForPeriod) {
    if (_blockTimestamp <= _lastDistributionTime) {
      totalRewardsForPeriod = 0;
    } else {
      totalRewardsForPeriod = _rewardAmountPerSecond.mul(_blockTimestamp - _lastDistributionTime);
    }
  }

  /// @notice Utility function to calculate amount of rewards pool can receive
  /// @dev Pure function for easier testing
  /// @param _poolTvl Pool's total value
  /// @param _eligiblePoolsTvl All eligible pools' total value
  /// @param _rewardsToDistribute Total amount of reward token ready to be distributed
  /// @return amount Reward token amount for a pool
  function calculatePoolRewardAmount(
    uint256 _poolTvl,
    uint256 _eligiblePoolsTvl,
    uint256 _rewardsToDistribute
  ) public pure returns (uint256 amount) {
    if (_eligiblePoolsTvl == 0 || _poolTvl > _eligiblePoolsTvl) {
      amount = 0;
    } else {
      amount = _rewardsToDistribute.mul(_poolTvl).div(_eligiblePoolsTvl);
    }
  }

  /// @notice Prepares list of pools and their corresponding rewards
  /// @return rewards List of entities (pool address and reward amount)
  /// @return totalRewardsToDistribute Total reward amount for distribution to eligible pools
  function calculateEligiblePoolsRewards()
    public
    view
    returns (RewardSummary[] memory rewards, uint256 totalRewardsToDistribute)
  {
    (uint256 eligiblePoolsTvl, address[] memory eligiblePools) = getEligiblePoolsWithTvl();
    uint256 totalRewardsForPeriod = calculateTotalRewardsForPeriod(
      rewardAmountPerSecond,
      lastDistributionTime,
      block.timestamp
    );
    uint256 poolsCount = eligiblePools.length;
    rewards = new RewardSummary[](poolsCount);
    for (uint256 i = 0; i < poolsCount; i++) {
      uint256 amount = calculatePoolRewardAmount(
        IPoolManagerLogic(IPoolLogic(eligiblePools[i]).poolManagerLogic()).totalFundValue(),
        eligiblePoolsTvl,
        totalRewardsForPeriod
      );
      RewardSummary memory summary;
      summary.pool = eligiblePools[i];
      summary.amount = amount;
      rewards[i] = summary;
      totalRewardsToDistribute += amount;
    }
  }

  /// @notice Get APY figure from the rewards distribution
  /// @dev Assumes that if eligiblePoolsTvl is more than 0, eligiblePools are not empty and have at least one item listed
  /// @return apy APY figure (can be multiplied by 100 to get value in percents)
  function getRewardsAPY() public view returns (uint256 apy) {
    (uint256 eligiblePoolsTvl, address[] memory eligiblePools) = getEligiblePoolsWithTvl();
    if (eligiblePoolsTvl == 0) {
      apy = 0;
    } else {
      apy = RewardsAPYCalculator.getAPY(
        eligiblePoolsTvl,
        rewardAmountPerSecond,
        IPoolLogic(eligiblePools[0]).factory(),
        address(rewardToken)
      );
    }
  }

  /** Write public */

  /// @notice Function to be called by anyone, distributes amount of reward tokens available since last distribution
  /// @dev Will prevent distribution when eligible pools are not set
  /// @dev Will prevent distribution when reward token amount for distribution equals zero
  /// @dev Will prevent distribution if contract needs to be topped-up with reward token
  function distributeRewards() public {
    (RewardSummary[] memory rewards, uint256 totalRewardsToDistribute) = calculateEligiblePoolsRewards();
    uint256 balanceOfContract = rewardToken.balanceOf(address(this));
    require(rewards.length > 0, "no eligible pools or not set");
    require(totalRewardsToDistribute != 0, "nothing to distribute");
    require(balanceOfContract >= totalRewardsToDistribute, "not enough reward token");
    require(
      totalRewardsToDistribute <= rewardAmountPerSecond.mul(block.timestamp - lastDistributionTime),
      "overdistribution"
    );
    _distributeRewards(rewards);
    emit RewardsDistribution(rewards, totalRewardsToDistribute);
  }

  /** Write private */

  /// @notice Transfers reward tokens directly to pools
  /// @param _rewards List of pools and their corresponding reward amounts
  function _distributeRewards(RewardSummary[] memory _rewards) private whenNotPaused {
    lastDistributionTime = block.timestamp;
    for (uint256 i = 0; i < _rewards.length; i++) {
      rewardToken.safeTransfer(_rewards[i].pool, _rewards[i].amount);
    }
  }
}
