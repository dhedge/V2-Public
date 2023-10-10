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

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../../utils/TxDataUtils.sol";
import "../../../interfaces/guards/IGuard.sol";
import "../../../interfaces/velodrome/IVelodromeGauge.sol";
import "../../../interfaces/IPoolManagerLogic.sol";
import "../../../interfaces/IHasSupportedAsset.sol";

/// @notice Transaction guard for Velodrome Gauge
contract VelodromeGaugeContractGuard is TxDataUtils, IGuard {
  event Claim(address fundAddress, address stakingContract, uint256 time);
  event Stake(address fundAddress, address stakingToken, address stakingContract, uint256 amount, uint256 time);
  event Unstake(address fundAddress, address stakingToken, address stakingContract, uint256 amount, uint256 time);

  /// @notice Transaction guard for Velodrome
  /// @dev It supports exchange, addLiquidity and removeLiquidity functionalities
  /// @param _poolManagerLogic the pool manager logic
  /// @param to the gauge address
  /// @param data the transaction data
  /// @return txType the transaction type of a given transaction data. 2 for `Exchange` type, 3 for `Add Liquidity`, 4 for `Remove Liquidity`
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
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();
    IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(_poolManagerLogic);

    bytes4 method = getMethod(data);
    bytes memory params = getParams(data);
    if (method == IVelodromeGauge.deposit.selector) {
      (uint256 amount, ) = abi.decode(params, (uint256, uint256));

      address stakeToken = IVelodromeGauge(to).stake();
      require(poolManagerLogicAssets.isSupportedAsset(stakeToken), "unsupported lp asset");

      emit Stake(poolLogic, stakeToken, to, amount, block.timestamp);

      txType = 5; // `Stake` type
    } else if (method == IVelodromeGauge.depositAll.selector) {
      address stakeToken = IVelodromeGauge(to).stake();
      require(poolManagerLogicAssets.isSupportedAsset(stakeToken), "unsupported lp asset");

      emit Stake(poolLogic, stakeToken, to, IERC20(stakeToken).balanceOf(poolLogic), block.timestamp);

      txType = 5; // `Stake` type
    } else if (method == IVelodromeGauge.withdraw.selector) {
      uint256 amount = abi.decode(params, (uint256));

      address stakeToken = IVelodromeGauge(to).stake();
      require(poolManagerLogicAssets.isSupportedAsset(stakeToken), "unsupported lp asset");

      emit Unstake(poolLogic, stakeToken, to, amount, block.timestamp);

      txType = 6; // `Unstake` type
    } else if (method == IVelodromeGauge.withdrawAll.selector) {
      address stakeToken = IVelodromeGauge(to).stake();
      require(poolManagerLogicAssets.isSupportedAsset(stakeToken), "unsupported lp asset");

      emit Unstake(poolLogic, stakeToken, to, IVelodromeGauge(to).balanceOf(poolLogic), block.timestamp);

      txType = 6; // `Unstake` type
    } else if (method == IVelodromeGauge.getReward.selector) {
      (address account, address[] memory tokens) = abi.decode(params, (address, address[]));

      for (uint256 i = 0; i < tokens.length; i++) {
        require(poolManagerLogicAssets.isSupportedAsset(tokens[i]), "unsupported reward token");
      }
      require(account == poolLogic, "invalid claimer");

      emit Claim(poolLogic, to, block.timestamp);

      txType = 7; // `Claim` type
    }

    return (txType, false);
  }
}
