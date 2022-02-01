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

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

import "../../utils/TxDataUtils.sol";
import "../../interfaces/guards/IGuard.sol";
import "../../interfaces/IPoolManagerLogic.sol";
import "../../interfaces/IHasSupportedAsset.sol";
import "../../interfaces/sushi/IMiniChefV2.sol";

/// @title Transaction guard for Sushi's MiniChefV2 staking contract
contract SushiMiniChefV2Guard is TxDataUtils, IGuard {
  using SafeMathUpgradeable for uint256;

  event Stake(address fundAddress, address asset, address stakingContract, uint256 amount, uint256 time);
  event Unstake(address fundAddress, address asset, address stakingContract, uint256 amount, uint256 time);
  event Claim(address fundAddress, address stakingContract, uint256 time);

  // The staking contract rewards in dual tokens.
  address[] public rewardTokens;

  constructor(address[] memory _rewardTokens) {
    rewardTokens = _rewardTokens;
  }

  /// @notice Transaction guard for Sushi MiniChefV2
  /// @dev It supports deposit, withdraw, harvest, withdrawAndHarvest functionalities
  /// @param _poolManagerLogic the pool manager logic
  /// @param to The contract to send transaction to
  /// @param data The transaction data
  /// @return txType the transaction type of a given transaction data. 5 for `Stake` type, 6 for `Unstake`, 7 for `Claim`, 8 for `UnstakeAndClaim`
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
    bytes4 method = getMethod(data);

    if (method == bytes4(keccak256("deposit(uint256,uint256,address)"))) {
      IPoolManagerLogic poolManagerLogic = IPoolManagerLogic(_poolManagerLogic);
      address poolLogic = poolManagerLogic.poolLogic();

      uint256 poolId = uint256(getInput(data, 0)); // The index of the pool in MiniChefV2.
      uint256 amount = uint256(getInput(data, 1)); // Amount LP token amount to stake.
      address receiver = convert32toAddress(getInput(data, 2)); // The receiver of `amount` staked LP tokens.
      address lpToken = IMiniChefV2(to).lpToken(poolId); // Sushi LP token to stake.

      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(lpToken), "unsupported lp asset");
      require(poolLogic == receiver, "recipient is not pool");
      for (uint256 i = 0; i < rewardTokens.length; i++) {
        require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(rewardTokens[i]), "enable reward token");
      }

      emit Stake(poolLogic, lpToken, to, amount, block.timestamp);

      txType = 5; // `Stake` type
    } else if (method == bytes4(keccak256("withdraw(uint256,uint256,address)"))) {
      IPoolManagerLogic poolManagerLogic = IPoolManagerLogic(_poolManagerLogic);
      address poolLogic = poolManagerLogic.poolLogic();
      uint256 poolId = uint256(getInput(data, 0)); // The index of the pool in MiniChefV2.
      uint256 amount = uint256(getInput(data, 1)); // Amount LP token amount to unstake.
      address receiver = convert32toAddress(getInput(data, 2)); // The receiver of `amount` staked LP tokens.
      address lpToken = IMiniChefV2(to).lpToken(poolId); // Sushi LP token to unstake.

      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(lpToken), "unsupported lp asset");
      require(poolLogic == receiver, "recipient is not pool");

      emit Unstake(poolLogic, lpToken, to, amount, block.timestamp);

      txType = 6; // `Unstake` type
    } else if (method == bytes4(keccak256("harvest(uint256,address)"))) {
      IPoolManagerLogic poolManagerLogic = IPoolManagerLogic(_poolManagerLogic);
      address poolLogic = poolManagerLogic.poolLogic();
      address receiver = convert32toAddress(getInput(data, 1)); // The receiver of the SUSHI rewards.

      for (uint256 i = 0; i < rewardTokens.length; i++) {
        require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(rewardTokens[i]), "enable reward token");
      }
      require(poolLogic == receiver, "recipient is not pool");

      emit Claim(poolLogic, to, block.timestamp);

      txType = 7; // `Claim` type
      isPublic = true;
    } else if (method == bytes4(keccak256("withdrawAndHarvest(uint256,uint256,address)"))) {
      IPoolManagerLogic poolManagerLogic = IPoolManagerLogic(_poolManagerLogic);
      address poolLogic = poolManagerLogic.poolLogic();
      uint256 poolId = uint256(getInput(data, 0)); // The index of the pool in MiniChefV2.
      uint256 amount = uint256(getInput(data, 1)); // Amount LP token amount to unstake.
      address receiver = convert32toAddress(getInput(data, 2)); // The receiver of `amount` staked LP tokens.
      address lpToken = address(IMiniChefV2(to).lpToken(poolId)); // Sushi LP token to unstake.

      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(lpToken), "unsupported lp asset");
      require(poolLogic == receiver, "recipient is not pool");
      for (uint256 i = 0; i < rewardTokens.length; i++) {
        require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(rewardTokens[i]), "enable reward token");
      }

      emit Unstake(poolLogic, lpToken, to, amount, block.timestamp);
      emit Claim(poolLogic, to, block.timestamp);

      txType = 8; // `UnstakeAndClaim` type
    } else if (method == bytes4(keccak256("emergencyWithdraw(uint256,address)"))) {
      IPoolManagerLogic poolManagerLogic = IPoolManagerLogic(_poolManagerLogic);
      address poolLogic = poolManagerLogic.poolLogic();
      uint256 poolId = uint256(getInput(data, 0)); // The index of the pool in MiniChefV2.
      address receiver = convert32toAddress(getInput(data, 1)); // The receiver of all the staked LP tokens.
      address lpToken = IMiniChefV2(to).lpToken(poolId); // Sushi LP token to unstake.
      (uint256 amount, ) = IMiniChefV2(to).userInfo(poolId, receiver); // Amount LP token amount that will be unstaked.

      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(lpToken), "unsupported lp asset");
      require(poolLogic == receiver, "recipient is not pool");

      emit Unstake(poolLogic, lpToken, to, amount, block.timestamp);

      txType = 6; // `Unstake` type
    }
  }
}
