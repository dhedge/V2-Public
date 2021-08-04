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
import "../../interfaces/sushi/IMiniChefV2.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

/// @title Sushi LP token asset guard
/// @dev Asset type = 2
contract SushiLPAssetGuard is ERC20Guard, Ownable {
  using SafeMathUpgradeable for uint256;

  struct SushiPool {
    address lpToken;
    uint256 stakingPoolId;
  }

  address public sushiStaking; // Sushi's staking MiniChefV2 contract

  mapping(address => uint256) public sushiPoolIds; // Sushi's staking MiniChefV2 Pool IDs

  event SushiPoolAdded(address indexed lpToken, uint256 indexed poolId);

  /// @notice Initialise for the contract
  /// @dev Set up the sushiPoolIds mapping from sushiStaking contract
  /// @param _sushiStaking Sushi's staking MiniChefV2 contract
  constructor(address _sushiStaking) {
    sushiStaking = _sushiStaking;
    IMiniChefV2 sushiMiniChefV2 = IMiniChefV2(sushiStaking);
    for (uint256 i = 0; i < sushiMiniChefV2.poolLength(); i++) {
      sushiPoolIds[sushiMiniChefV2.lpToken(i)] = i;
    }
  }

  /// @notice Creates transaction data for withdrawing staked tokens
  /// @dev The same interface can be used for other types of stakeable tokens
  /// @param pool Pool address
  /// @param asset Staked asset
  /// @param portion The fraction of total staked asset to withdraw
  /// @param to The investor address to withdraw to
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
    withdrawAsset = asset;
    uint256 totalAssetBalance = IERC20(asset).balanceOf(pool);
    withdrawBalance = totalAssetBalance.mul(portion).div(10**18);

    uint256 sushiPoolId = sushiPoolIds[asset];
    (uint256 stakedBalance, ) = IMiniChefV2(sushiStaking).userInfo(sushiPoolId, pool);

    // If there is a staked balance in Sushi MiniChefV2 staking contract
    // Then create the withdrawal transaction data to be executed by PoolLogic
    if (stakedBalance > 0) {
      uint256 withdrawAmount = stakedBalance.mul(portion).div(10**18);
      if (withdrawAmount > 0) {
        transactions = new MultiTransaction[](1);
        transactions[0].to = sushiStaking;
        transactions[0].txData = abi.encodeWithSelector(
          bytes4(keccak256("withdraw(uint256,uint256,address)")),
          sushiPoolId,
          withdrawAmount,
          to
        );
      }
    }
  }

  /// @notice Returns the balance of the managed asset
  /// @dev May include any external balance in staking contracts
  /// @param pool address of the pool
  /// @param asset address of the asset
  /// @return balance The asset balance of given pool
  function getBalance(address pool, address asset) public view override returns (uint256 balance) {
    uint256 sushiPoolId = sushiPoolIds[asset];
    (uint256 stakedBalance, ) = IMiniChefV2(sushiStaking).userInfo(sushiPoolId, pool);
    uint256 poolBalance = IERC20(asset).balanceOf(pool);
    balance = stakedBalance.add(poolBalance);
  }

  /// @notice Setting sushi pool Id
  /// @param lpToken address of the LP Token
  /// @param poolId Id of LP pair pool
  function setSushiPoolId(address lpToken, uint256 poolId) external onlyOwner {
    require(lpToken != address(0), "Invalid lpToken address");

    sushiPoolIds[lpToken] = poolId;
    emit SushiPoolAdded(lpToken, poolId);
  }
}
