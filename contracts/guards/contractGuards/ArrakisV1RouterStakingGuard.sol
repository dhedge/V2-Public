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
import "../../interfaces/guards/IGuard.sol";
import "../../interfaces/IHasAssetInfo.sol";
import "../../interfaces/IPoolLogic.sol";
import "../../interfaces/IPoolManagerLogic.sol";
import "../../interfaces/IHasSupportedAsset.sol";
import "../../interfaces/arrakis/IArrakisV1RouterStaking.sol";
import "../../interfaces/arrakis/ILiquidityGaugeV4.sol";
import "../../interfaces/arrakis/IArrakisVaultV1.sol";

/// @title Transaction guard for Arrakis Finance's Uniswap V3 LP liquidity mining
contract ArrakisV1RouterStakingGuard is TxDataUtils, IGuard {
  using SafeMathUpgradeable for uint256;

  event Stake(address fundAddress, address stakingToken, address stakingContract, uint256 time);
  event Unstake(address fundAddress, address stakingToken, address stakingContract, uint256 amount, uint256 time);

  /// @notice Transaction guard for Arrakis Finance V1 Router Staking
  /// @dev It supports stake and unstake functionalities
  /// @param _poolManagerLogic the pool manager logic
  /// @param to The contract to send transaction to
  /// @param data The transaction data
  /// @return txType the transaction type of a given transaction data. 5 for `Stake` type, 6 for `Unstake`
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
      bool // isPublic
    )
  {
    IPoolManagerLogic poolManagerLogic = IPoolManagerLogic(_poolManagerLogic);
    IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(_poolManagerLogic);

    bytes4 method = getMethod(data);
    if (method == IArrakisV1RouterStaking.addLiquidityAndStake.selector) {
      (address gauge, , , , , , address receiver) = abi.decode(
        getParams(data),
        (address, uint256, uint256, uint256, uint256, uint256, address)
      );

      address stakingToken = ILiquidityGaugeV4(gauge).staking_token();
      IArrakisVaultV1 vault = IArrakisVaultV1(stakingToken);

      require(poolManagerLogicAssets.isSupportedAsset(gauge), "unsupported gauge token");
      require(poolManagerLogicAssets.isSupportedAsset(vault.token0()), "unsupported asset: token0");
      require(poolManagerLogicAssets.isSupportedAsset(vault.token1()), "unsupported asset: token1");
      checkRewardTokens(gauge, _poolManagerLogic, poolManagerLogic.poolLogic(), false);

      require(poolManagerLogic.poolLogic() == receiver, "receiver is not pool");

      emit Stake(poolManagerLogic.poolLogic(), stakingToken, to, block.timestamp);

      txType = 5; // `Stake` type
    } else if (method == IArrakisV1RouterStaking.removeLiquidityAndUnstake.selector) {
      (address gauge, uint256 burnAmount, , , address receiver) = abi.decode(
        getParams(data),
        (address, uint256, uint256, uint256, address)
      );
      address stakingToken = ILiquidityGaugeV4(gauge).staking_token();
      IArrakisVaultV1 vault = IArrakisVaultV1(stakingToken);

      require(poolManagerLogicAssets.isSupportedAsset(gauge), "unsupported gauge token");
      require(poolManagerLogicAssets.isSupportedAsset(vault.token0()), "unsupported asset: token0");
      require(poolManagerLogicAssets.isSupportedAsset(vault.token1()), "unsupported asset: token1");
      checkRewardTokens(gauge, _poolManagerLogic, poolManagerLogic.poolLogic(), true);

      require(poolManagerLogic.poolLogic() == receiver, "receiver is not pool");

      emit Unstake(poolManagerLogic.poolLogic(), stakingToken, to, burnAmount, block.timestamp);

      txType = 6; // `Unstake` type
    }

    return (txType, false);
  }

  function checkRewardTokens(
    address gauge,
    address poolManagerLogic,
    address poolLogic,
    bool checkClaimableAmount
  ) internal view {
    address factory = IPoolLogic(poolLogic).factory();
    uint256 rewardCount = ILiquidityGaugeV4(gauge).reward_count();
    for (uint256 i = 0; i < rewardCount; i++) {
      address rewardToken = ILiquidityGaugeV4(gauge).reward_tokens(i);
      if (!checkClaimableAmount || ILiquidityGaugeV4(gauge).claimable_reward(poolLogic, rewardToken) > 0) {
        require(
          !IHasAssetInfo(factory).isValidAsset(rewardToken) ||
            IHasSupportedAsset(poolManagerLogic).isSupportedAsset(rewardToken),
          "enable reward token"
        );
      }
    }
  }
}
