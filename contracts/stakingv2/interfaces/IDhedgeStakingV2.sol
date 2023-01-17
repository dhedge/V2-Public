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

import "./IDhedgeStakingV2Storage.sol";

interface IDhedgeStakingV2 {
  /// @notice Create a new stake with DHT
  /// @dev After creating dht stake user can stake Pool Tokens. User needs to approve this contract for dht first.
  /// @param dhtAmount the amount of dht being staked
  function newStake(uint256 dhtAmount) external returns (uint256 tokenId);

  /// @notice Allows the user to add addtional amount of DHT to an existing stake
  /// @dev After creating dht stake user can stake Pool Tokens. User needs to approve this contract for dht first.
  /// @param tokenId The erc721 id of the existing stake
  /// @param dhtAmount the amount of additional dht to be staked
  function addDhtToStake(uint256 tokenId, uint256 dhtAmount) external;

  /// @notice Allows the user to unstake all or some of their dht from a given stake
  /// @dev if the user calls this before calling unstakePoolTokens they may miss out on rewards
  /// @param tokenId The erc721 id of the existing stake
  /// @param dhtAmount the amount of dht they want to unstaked
  function unstakeDHT(uint256 tokenId, uint256 dhtAmount) external;

  /// @notice Allows the user to stake dhedge pool tokens with an existing DHT Stake
  /// @dev After creating dht stake user can stake Pool Tokens. User needs to approve this contract for dhedgePoolAddress first.
  /// @param tokenId The erc721 id of the existing stake
  /// @param dhedgePoolAddress the address of the pool being staked
  /// @param dhedgePoolAmount the amount of pool tokens being staked
  function stakePoolTokens(
    uint256 tokenId,
    address dhedgePoolAddress,
    uint256 dhedgePoolAmount
  ) external;

  /// @notice Allows the user to unstake their dhedge pool tokens, when called will be allocated rewards at this point.
  /// @dev Once the user unstakes their pooltokens the rewards to be recieved are calculated and assigned to the user. This stake is retired.
  /// @dev DHT is automatically zapped to a new stake that maintains it's existing vDHT. A user can then stake new pool tokens against these dht, or unstake the DHT.
  /// @param tokenId The erc721 id of the existing stake
  /// @return newTokenId the tokenId where the dht were zapped to.
  function unstakePoolTokens(uint256 tokenId) external returns (uint256 newTokenId);

  /// @notice Allows the user to claim their unlocked rewards for a given stake. The rewards are unlocked over rewardStreamingTime
  /// @dev If rewardStreamingTime == 7 days on day 7 they will be able to claim 100% of their rewards. On day 1 they will only be able to claim 1/7th.
  /// @param tokenId The erc721 id of the existing stake
  function claim(uint256 tokenId) external;

  /// @notice Returns the amount of rewards unlocked so far for a given stake
  /// @dev If rewardStreamingTime == 7 days on day 7 they will be able to claim 100% of their rewards. On day 1 they will only be able to claim 1/7th.
  /// @param tokenId The erc721 id of the existing stake
  function canClaimAmount(uint256 tokenId) external returns (uint256);

  /// @notice The aggregate DHT balance of the wallet
  /// @param staker The the wallet
  function dhtBalanceOf(address staker) external view returns (uint256 dht);

  /// @notice The aggregate vDHT balance of the wallet
  /// @dev Can be used for voting
  /// @param staker The the wallet
  /// @return vDHT the current vDHT for the given wallet
  function vDHTBalanceOf(address staker) external view returns (uint256 vDHT);

  /// @notice Returns the current vDHT of a stake
  /// @dev this changes every block based on the time passed since staking
  /// @param tokenId the id of the stake
  /// @return vDHT the current vDHT for the given stake
  function vDHTBalanceOfStake(uint256 tokenId) external view returns (uint256 vDHT);

  /// @notice Allows getting configuration of a pool
  /// @param poolAddress the dhedge pool address to get the configuration for
  /// @return poolConfiguration the configuration for the given pool
  function getPoolConfiguration(address poolAddress)
    external
    view
    returns (IDhedgeStakingV2Storage.PoolConfiguration memory);

  /// @notice Allows getting stake info
  /// @param tokenId the erc721 id of the stake
  /// @return stake the stake struct for the given tokenID
  function getStake(uint256 tokenId) external view returns (IDhedgeStakingV2Storage.Stake memory);

  /// @notice The rewards a staker would receive if they unstaked now
  /// @param tokenId the id of the stake
  /// @return rewardsDHT the current aggregate DHT for the address
  function currentRewardsForStake(uint256 tokenId) external view returns (uint256 rewardsDHT);
}
