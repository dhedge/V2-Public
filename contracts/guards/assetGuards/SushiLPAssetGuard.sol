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
// Copyright (c) 2020 dHEDGE DAO
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

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";

import "./ERC20Guard.sol";
import "../IAssetGuard.sol";
import "../../utils/TxDataUtils.sol";
import "../../interfaces/IPoolManagerLogic.sol";
import "../../interfaces/IHasGuardInfo.sol";
import "../../interfaces/IManaged.sol";
import "../../interfaces/sushi/IMiniChefV2.sol";

/// @title Sushi LP token asset guard
/// @dev Asset type = 2
/// @dev Asset types > 0 must also inherit from IAssetGuard
contract SushiLPAssetGuard is TxDataUtils, ERC20Guard, IAssetGuard {
  using SafeMath for uint256;

  struct SushiPool {
    address lpToken;
    uint256 stakingPoolId;
  }

  address public sushiStaking; // Sushi's staking MiniChefV2 contract

  mapping(address => uint256) public sushiPoolIds; // Sushi's staking MiniChefV2 Pool IDs

  event WithdrawStaked(address fundAddress, address asset, address to, uint256 withdrawAmount, uint256 time);

  /// @param _sushiStaking Sushi's staking MiniChefV2 contract
  /// @param sushiPools For mapping Sushi LP tokens to MiniChefV2 pool IDs
  constructor(address _sushiStaking, SushiPool[] memory sushiPools) public {
    sushiStaking = _sushiStaking;
    for (uint256 i = 0; i < sushiPools.length; i++) {
      sushiPoolIds[sushiPools[i].lpToken] = sushiPools[i].stakingPoolId;
    }
  }

  /// @notice Creates transaction data for withdrawing staked tokens
  /// @dev The same interface can be used for other types of stakeable tokens
  /// @param pool Pool address
  /// @param asset Staked asset
  /// @param withdrawPortion The fraction of total staked asset to withdraw
  /// @param to The investor address to withdraw to
  /// @return stakingContract and txData are used to execute the staked withdrawal transaction in PoolLogic
  function getWithdrawStakedTx(
    address pool,
    address asset,
    uint256 withdrawPortion,
    address to
  ) external override returns (address stakingContract, bytes memory txData) {
    uint256 sushiPoolId = sushiPoolIds[asset];
    (uint256 stakedBalance, ) = IMiniChefV2(sushiStaking).userInfo(sushiPoolId, pool);

    // If there is a staked balance in Sushi MiniChefV2 staking contract
    // Then create the withdrawal transaction data to be executed by PoolLogic
    if (stakedBalance > 0) {
      stakingContract = sushiStaking;
      uint256 withdrawAmount = stakedBalance.mul(withdrawPortion).div(10**18);
      if (withdrawAmount > 0) {
        txData = abi.encodeWithSelector(
          bytes4(keccak256("withdrawAndHarvest(uint256, uint256, address)")),
          sushiPoolId,
          withdrawAmount,
          to
        );
        emit WithdrawStaked(pool, asset, to, withdrawAmount, block.timestamp);
      }
    }
  }
}
