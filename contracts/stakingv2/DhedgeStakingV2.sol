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

import "../interfaces/IPoolLogic.sol";
import "./interfaces/IDhedgeStakingV2.sol";
import "./Base64.sol";
import "./DhedgeStakingV2VDHTCalculator.sol";
import "./DhedgeStakingV2Storage.sol";
import "./DhedgeStakingV2RewardsCalculator.sol";
import "./DhedgeStakingV2NFTJson.sol";

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract DhedgeStakingV2 is
  IDhedgeStakingV2,
  DhedgeStakingV2Storage,
  DhedgeStakingV2VDHTCalculator,
  DhedgeStakingV2RewardsCalculator,
  ERC721Upgradeable,
  PausableUpgradeable,
  ReentrancyGuardUpgradeable
{
  using SafeMath for uint256;
  using SafeERC20Upgradeable for IERC20Upgradeable;
  using CountersUpgradeable for CountersUpgradeable.Counter;

  event NewStake(uint256 tokenId, uint256 dhtAmount);
  event AddDHTToStake(uint256 tokenId, uint256 dhtAmount);
  event StakePoolTokens(uint256 tokenId, address dhedgePoolAddress, uint256 poolTokenAmount);
  event UnstakePoolTokens(uint256 tokenId, uint256 newTokedId);
  event UnstakeDHT(uint256 tokenId);
  event Claim(uint256 tokenId, uint256 claimAmount);

  function initialize(address _dhtAddress) external initializer {
    __ERC721_init("DhedgeStakingV2", "DHTSV2");
    __Ownable_init();
    __Pausable_init();
    __ReentrancyGuard_init();
    require(_dhtAddress != address(0), "dhtAddress is required");
    dhtAddress = _dhtAddress;
    dhtCap = 1_000_000 * 10**18;
    rewardStreamingTime = 7 days;
    maxVDurationTimeSeconds = 273 days; // 9 Months
    rewardParams = RewardParams({
      stakeDurationDelaySeconds: 30 days,
      maxDurationBoostSeconds: 273 days, // 9 Months
      maxPerformanceBoostNumerator: 500, // 50%
      maxPerformanceBoostDenominator: 1000,
      stakingRatio: 6,
      emissionsRate: 1500,
      emissionsRateDenominator: 1000
    });
  }

  /// @notice implementations should not be left unintialized
  // solhint-disable-next-line no-empty-blocks
  function implInitializer() external initializer {}

  /// OVERRIDE

  /// @notice Stops the transfering of the token that represents a stake
  /// @param from address(0) when minting
  /// @param to address(0) when burning
  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 tokenId
  ) internal virtual override {
    require(to == address(0) || from == address(0), "Token is soulbound");
    super._beforeTokenTransfer(from, to, tokenId);
  }

  /// WRITE External

  /// @notice Create a new stake
  /// @dev User needs to approve this contract for dhtAmount.
  /// @param dhtAmount the amount of dht being staked
  /// @return tokenId the erc721 tokenId
  function newStake(uint256 dhtAmount) external override whenNotPaused nonReentrant returns (uint256 tokenId) {
    if (dhtAmount > 0) {
      IERC20Upgradeable(dhtAddress).safeTransferFrom(msg.sender, address(this), dhtAmount);
    }
    tokenId = _newStake(msg.sender, dhtAmount, block.timestamp);
    _addToGlobalStake(dhtAmount);
    emit NewStake(tokenId, dhtAmount);
  }

  /// @notice Add additional DHT
  /// @dev User needs to approve this contract for DHT first
  /// @param tokenId the erc721 tokenId
  /// @param dhtAmount the amount of dht being staked
  function addDhtToStake(uint256 tokenId, uint256 dhtAmount) external override whenNotPaused nonReentrant {
    require(_isApprovedOrOwner(msg.sender, tokenId), "Must be approved or owner.");
    require(stakes[tokenId].unstaked == false, "Already unstaked");
    require(dhtAmount > 0, "Must add some dht");
    IERC20Upgradeable(dhtAddress).safeTransferFrom(msg.sender, address(this), dhtAmount);
    _addAdditionalDHTToStake(tokenId, dhtAmount);
    _addToGlobalStake(dhtAmount);
    emit AddDHTToStake(tokenId, dhtAmount);
  }

  /// @notice Returns a users staked DHT and if empty burns the nft
  /// @dev This should only be called on an empty stake (i.e no pooltokens staked), otherwise can miss out on rewards
  /// @param tokenId the tokenId that represents the Stake
  function unstakeDHT(uint256 tokenId, uint256 dhtAmount) external override whenNotPaused nonReentrant {
    require(_isApprovedOrOwner(msg.sender, tokenId), "Must be approved or owner.");
    IDhedgeStakingV2Storage.Stake storage stake = stakes[tokenId];
    require(stake.dhtAmount >= dhtAmount, "Not enough staked dht.");
    uint256 vDHTBefore = vDHTBalanceOfStake(tokenId);
    stake.dhtAmount = stake.dhtAmount.sub(dhtAmount);
    uint256 vDHTAfter = vDHTBalanceOfStake(tokenId);
    _removeFromGlobalStake(dhtAmount, vDHTBefore.sub(vDHTAfter));
    IERC20Upgradeable(dhtAddress).safeTransfer(msg.sender, dhtAmount);
    emit UnstakeDHT(tokenId);
  }

  /// @param dhedgePoolAddress the address of pool that is being staked
  /// @param dhedgePoolAmount Amount of Pool tokens being staked
  function stakePoolTokens(
    uint256 tokenId,
    address dhedgePoolAddress,
    uint256 dhedgePoolAmount
  ) external override whenNotPaused nonReentrant {
    require(_isApprovedOrOwner(msg.sender, tokenId), "Must be approved or owner.");
    _checkPoolConfigured(dhedgePoolAddress);
    IDhedgeStakingV2Storage.Stake storage stake = stakes[tokenId];
    require(stake.unstaked == false, "Already unstaked");
    require(stake.dhedgePoolAddress == address(0), "Pool Tokens already staked.");

    IERC20Upgradeable(dhedgePoolAddress).safeTransferFrom(msg.sender, address(this), dhedgePoolAmount);

    uint256 tokenPrice = IPoolLogic(dhedgePoolAddress).tokenPrice();
    uint256 totalDepositValue = tokenPrice.mul(dhedgePoolAmount).div(10**18);
    poolConfiguration[dhedgePoolAddress].stakedSoFar = poolConfiguration[dhedgePoolAddress].stakedSoFar.add(
      totalDepositValue
    );
    _checkPoolCap(dhedgePoolAddress);

    // Not sure if we still want to have the global limit in addition to per pool limits
    totalStakingValue = totalStakingValue.add(totalDepositValue);
    _checkMaxStaking();

    stake.dhedgePoolAddress = dhedgePoolAddress;
    stake.dhedgePoolAmount = dhedgePoolAmount;
    stake.stakeStartTokenPrice = tokenPrice;
    stake.dhedgePoolStakeStartTime = block.timestamp;
    // The staking contract is a whitelisted receiver and therefore it should enforce the token lockup
    stake.dhedgePoolRemainingExitCooldownAtStakeTime = IPoolLogic(dhedgePoolAddress).getExitRemainingCooldown(
      msg.sender
    );
    emit StakePoolTokens(tokenId, stake.dhedgePoolAddress, stake.dhedgePoolAmount);
  }

  /// @notice Allows the user to unstake their dhedge pool tokens, when called will be allocated rewards at this point.
  /// @dev Once the user unstakes their pooltokens the rewards to be recieved are calculated and assigned to the user. This stake is retired.
  /// @dev DHT is automatically zapped to a new stake that maintains it's existing vDHT. A user can then stake new pool tokens against these dht, or unstake the DHT.
  /// @param tokenId The erc721 id of the existing stake
  /// @return newTokenId the tokenId where the dht were zapped to.
  function unstakePoolTokens(uint256 tokenId)
    external
    override
    whenNotPaused
    nonReentrant
    returns (uint256 newTokenId)
  {
    require(_isApprovedOrOwner(msg.sender, tokenId), "Must be approved or owner.");
    IDhedgeStakingV2Storage.Stake storage stake = stakes[tokenId];
    require(
      stake.dhedgePoolStakeStartTime.add(stake.dhedgePoolRemainingExitCooldownAtStakeTime) < block.timestamp,
      "cooldown active"
    );
    require(stake.unstaked == false, "Already unstaked");
    require(stake.dhedgePoolAddress != address(0), "No pool tokens staked");
    stake.unstaked = true;
    stake.unstakeTime = block.timestamp;

    uint256 tokenPriceFinish = IPoolLogic(stake.dhedgePoolAddress).tokenPrice();
    stake.stakeFinishTokenPrice = tokenPriceFinish;
    uint256 vhdt = vDHTBalanceOfStake(tokenId);
    stake.vdhtAccruedAtUnstake = vhdt;
    // Staker only receives rewards if they've staked for minimum stake time
    if (block.timestamp.sub(stake.dhedgePoolStakeStartTime) >= rewardParams.stakeDurationDelaySeconds) {
      stake.reward = calculateDhtRewardAmount(
        vhdt,
        stake.dhedgePoolAmount,
        stake.stakeStartTokenPrice,
        tokenPriceFinish,
        stake.dhedgePoolStakeStartTime,
        block.timestamp,
        stake.rewardParamsEmissionsRate,
        rewardParams
      );
    }

    uint256 stakedDhtAmount = stake.dhtAmount;
    stake.dhtAmount = 0;
    // Once pool tokens have been claimed we teleport the staked DHT to a new Stake
    // The existing stake is used for claiming the rewards
    newTokenId = _newStake(ownerOf(tokenId), stakedDhtAmount, stake.dhtStakeStartTime);
    uint256 originalValueStaked = stake.stakeStartTokenPrice.mul(stake.dhedgePoolAmount).div(10**18);
    poolConfiguration[stake.dhedgePoolAddress].stakedSoFar = poolConfiguration[stake.dhedgePoolAddress].stakedSoFar.sub(
      originalValueStaked
    );

    totalStakingValue = totalStakingValue.sub(originalValueStaked);
    dhtRewarded = dhtRewarded.add(stake.reward);

    IERC20Upgradeable(stake.dhedgePoolAddress).safeTransfer(msg.sender, stake.dhedgePoolAmount);
    emit UnstakePoolTokens(tokenId, newTokenId);
  }

  /// @notice Used to claim rewards for an unstaked position
  /// @dev The user can claim all rewards once the rewardStreamingTime has passed or a pro-rate amount
  /// @param tokenId the tokenId that represents the Stake that has been unstaked
  function claim(uint256 tokenId) external override nonReentrant {
    require(_isApprovedOrOwner(msg.sender, tokenId), "Must be approved or owner.");
    IDhedgeStakingV2Storage.Stake storage stake = stakes[tokenId];
    require(stake.unstaked == true, "Not Unstaked.");
    uint256 claimAmount = canClaimAmount(tokenId);
    require(claimAmount > 0, "Nothing to claim");
    checkEnoughDht(claimAmount);
    stake.claimedReward = stake.claimedReward.add(claimAmount);

    require(stake.claimedReward <= stake.reward, "Claiming to much.");
    IERC20Upgradeable(dhtAddress).safeTransfer(msg.sender, claimAmount);
    emit Claim(tokenId, claimAmount);
  }

  /// WRITE Internal

  function _addToGlobalStake(uint256 dhtAmount) internal {
    uint256 target = globalVDHT();
    dhtStaked = dhtStaked.add(dhtAmount);
    uint256 unit = 10**18;
    if (dhtStaked > 0) {
      aggregateStakeStartTime = block.timestamp.sub(
        maxVDurationTimeSeconds.mul(target).mul(unit).div(dhtStaked).div(unit)
      );
    } else {
      aggregateStakeStartTime = 0;
    }
  }

  function _removeFromGlobalStake(uint256 dhtAmount, uint256 vDHTAccrued) internal {
    require(dhtAmount >= vDHTAccrued, "dhtAmount must be => vDHTAccrued");
    uint256 target = globalVDHT().sub(vDHTAccrued);
    dhtStaked = dhtStaked.sub(dhtAmount);
    uint256 unit = 10**18;
    if (dhtStaked == 0) {
      aggregateStakeStartTime = block.timestamp;
    } else {
      aggregateStakeStartTime = block.timestamp.sub(
        maxVDurationTimeSeconds.mul(target).mul(unit).div(dhtStaked).div(unit)
      );
    }
  }

  function globalVDHT() public view returns (uint256) {
    return calculateVDHT(aggregateStakeStartTime, dhtStaked, block.timestamp, maxVDurationTimeSeconds);
  }

  /// @notice Adjust an existing stake by the additionalDHT and reduces the stake time so vDHT remains consistent
  /// @dev this allows additional DHT to be staked, but prevents manipulation of rewards, cannot stake dht to unstaked/claimed staked
  /// @param tokenId the erc721 tokenId that represents the stake
  /// @param additionalDHT the additional amount of dht being staked
  function _addAdditionalDHTToStake(uint256 tokenId, uint256 additionalDHT) internal {
    require(additionalDHT > 0, "Must stake some additional dht.");
    IDhedgeStakingV2Storage.Stake storage stake = stakes[tokenId];
    require(stake.unstaked == false, "Already unstaked.");
    uint256 unit = 10**18;
    uint256 timePassed = block.timestamp - stake.dhtStakeStartTime;
    uint256 currentlyStaked = stake.dhtAmount;
    uint256 newStakeAmount = stake.dhtAmount.add(additionalDHT);
    // now - (((now - startTime)) * ((amountStaked * unit) /(additionalAmount + amountStaked))) / unit
    uint256 adjustment = timePassed.mul(currentlyStaked.mul(unit).div(newStakeAmount)).div(unit);
    stake.dhtStakeStartTime = block.timestamp.sub(adjustment);
    stake.dhtAmount = newStakeAmount;
  }

  /// @notice Creates a new DHT stake for the user with the given parameters
  /// @dev Must remain internal
  /// @param owner The owner of the stake to be created
  /// @param dhtAmount the amount of dht for the new stake
  /// @param stakeStartTime the time the stake should start from
  function _newStake(
    address owner,
    uint256 dhtAmount,
    uint256 stakeStartTime
  ) internal returns (uint256 newTokenId) {
    newTokenId = _mint(owner);
    stakes[newTokenId] = IDhedgeStakingV2Storage.Stake({
      dhtAmount: dhtAmount,
      dhtStakeStartTime: stakeStartTime,
      dhedgePoolAddress: address(0),
      dhedgePoolAmount: 0,
      dhedgePoolStakeStartTime: 0,
      dhedgePoolRemainingExitCooldownAtStakeTime: 0,
      stakeStartTokenPrice: 0,
      unstaked: false,
      unstakeTime: 0,
      reward: 0,
      claimedReward: 0,
      rewardParamsEmissionsRate: rewardParams.emissionsRate,
      stakeFinishTokenPrice: 0,
      vdhtAccruedAtUnstake: 0
    });
  }

  /// @notice Handles incrementing the tokenIdCounter and minting the nft
  /// @param to the stakers address
  function _mint(address to) internal returns (uint256 tokenId) {
    tokenId = _tokenIdCounter.current();
    _safeMint(to, tokenId);
    _tokenIdCounter.increment();
  }

  /// VIEW

  /// @notice Allows getting stake info
  /// @param tokenId the erc721 id of the stake
  /// @return stake the stake struct for the given tokenID
  function getStake(uint256 tokenId) external view override returns (Stake memory) {
    return stakes[tokenId];
  }

  /// @notice Calculates the max amount of DHPT value that can be currently staked
  /// @dev N.B this does not enforce the ratio the users stake at. It simply caps emissions under the circumstances where every staker stakes at the optimal ratio and maxes out their rewards
  /// @return maximumStakingValue The max amount of DHPT value that should currently be staked
  function maxStakingValue() public view returns (uint256 maximumStakingValue) {
    maximumStakingValue = dhtCap
      .sub(dhtRewarded)
      .div(rewardParams.stakingRatio)
      .mul(rewardParams.emissionsRateDenominator)
      .div(rewardParams.emissionsRate);
  }

  /// @notice Allows getting configuration of a pool
  /// @param dhedgePoolAddress the dhedge pool address to get the configuration for
  function getPoolConfiguration(address dhedgePoolAddress)
    external
    view
    override
    returns (IDhedgeStakingV2Storage.PoolConfiguration memory)
  {
    return poolConfiguration[dhedgePoolAddress];
  }

  /// @notice Returns the token holder amount can claim based on the time passed since they unstaked
  /// @dev The user can only claim a proportional amount until `rewardStreamingTime` has passed
  /// @param tokenId the tokenId that represents the Stake that has been unstaked
  /// @return claimAmount the amount the staker can claim
  function canClaimAmount(uint256 tokenId) public view override returns (uint256 claimAmount) {
    IDhedgeStakingV2Storage.Stake memory stake = stakes[tokenId];
    if (stake.unstakeTime == 0) {
      return 0;
    }
    uint256 rewardsPerSecond = stake.reward.div(rewardStreamingTime);
    uint256 timePassed = block.timestamp.sub(stake.unstakeTime);
    if (timePassed > rewardStreamingTime) {
      claimAmount = stake.reward.sub(stake.claimedReward);
    } else {
      uint256 canStream = rewardsPerSecond.mul(timePassed);
      claimAmount = canStream.sub(stake.claimedReward);
    }
  }

  /// @notice Returns the current vDHT of an address
  /// @dev this changes every block based on the time passed since staking
  /// @param staker the stakers address
  /// @return vDHT the current aggregate vDHT for the staker
  function vDHTBalanceOf(address staker) external view override returns (uint256 vDHT) {
    uint256 balance = balanceOf(staker);
    for (uint256 i = 0; i < balance; i++) {
      uint256 tokenId = tokenOfOwnerByIndex(staker, i);
      vDHT = vDHT.add(vDHTBalanceOfStake(tokenId));
    }
  }

  /// @notice Returns the current vDHT of a stake
  /// @dev this changes every block based on the time passed since staking
  /// @param tokenId the id of the stake
  /// @return vDHT the current vDHT for the given stake
  function vDHTBalanceOfStake(uint256 tokenId) public view override returns (uint256 vDHT) {
    IDhedgeStakingV2Storage.Stake memory stake = stakes[tokenId];
    if (stake.dhtAmount > 0) {
      vDHT = calculateVDHT(stake.dhtStakeStartTime, stake.dhtAmount, block.timestamp, maxVDurationTimeSeconds);
    }
  }

  /// @notice Returns the aggregate DHT staked of an address
  /// @param staker the stakers address
  /// @return dht the current aggregate DHT for the address
  function dhtBalanceOf(address staker) external view override returns (uint256 dht) {
    uint256 balance = balanceOf(staker);
    for (uint256 i = 0; i < balance; i++) {
      uint256 tokenId = tokenOfOwnerByIndex(staker, i);
      dht = dht.add(stakes[tokenId].dhtAmount);
    }
  }

  /// @notice The rewards a stake would receive if unstaked now
  /// @param tokenId the id of the stake
  /// @return rewardsDHT the current aggregate DHT for the address
  function currentRewardsForStake(uint256 tokenId) public view override returns (uint256 rewardsDHT) {
    IDhedgeStakingV2Storage.Stake memory stake = stakes[tokenId];
    if (stake.dhedgePoolAddress != address(0)) {
      uint256 currentTokenPrice = IPoolLogic(stake.dhedgePoolAddress).tokenPrice();
      rewardsDHT = calculateDhtRewardAmount(
        vDHTBalanceOfStake(tokenId),
        stake.dhedgePoolAmount,
        stake.stakeStartTokenPrice,
        currentTokenPrice,
        stake.dhedgePoolStakeStartTime,
        block.timestamp,
        stake.rewardParamsEmissionsRate,
        rewardParams
      );
    } else {
      rewardsDHT = 0;
    }
  }

  function tokenURI(uint256 tokenId) public view override returns (string memory) {
    IDhedgeStakingV2Storage.Stake memory stake = stakes[tokenId];
    string memory poolSymbol;
    uint256 currentTokenPrice;

    if (stake.dhedgePoolAddress != address(0)) {
      poolSymbol = IPoolLogic(stake.dhedgePoolAddress).symbol();
      currentTokenPrice = IPoolLogic(stake.dhedgePoolAddress).tokenPrice();
    }

    return
      tokenUriGenerator.tokenJson(
        tokenId,
        stake,
        vDHTBalanceOfStake(tokenId),
        currentRewardsForStake(tokenId),
        poolSymbol,
        currentTokenPrice,
        dhtAddress,
        ownerOf(tokenId)
      );
  }

  /// ASSERT

  /// @notice Check the dhedge pool being staked is on the allow list
  /// @param dhedgePoolAddress address of the dhedge pool
  function _checkPoolConfigured(address dhedgePoolAddress) internal view {
    require(poolConfiguration[dhedgePoolAddress].configured == true, "Pool not allowed.");
  }

  /// @notice Check the amount being staked doesnt exceed the pools configured cap
  /// @param dhedgePoolAddress address of the dhedge pool
  function _checkPoolCap(address dhedgePoolAddress) internal view {
    PoolConfiguration memory pc = poolConfiguration[dhedgePoolAddress];
    require(pc.stakedSoFar <= pc.stakeCap, "Cap for pool will be exceeded.");
  }

  /// @notice Check here that the amount of value being staked isn't more than the max
  /// @dev This can help control emissions
  function _checkMaxStaking() internal view {
    require(totalStakingValue <= maxStakingValue(), "Staking cap will be exceeded.");
  }

  /// @notice Check here we don't distribute any staked DHT as rewards
  /// @param claimAmount the amount of dht attempting to be claimed
  function checkEnoughDht(uint256 claimAmount) public view {
    uint256 balanceNotStaked = IERC20Upgradeable(dhtAddress).balanceOf(address(this)).sub(dhtStaked);
    require(balanceNotStaked >= claimAmount, "Rewards depleted.");
  }
}
