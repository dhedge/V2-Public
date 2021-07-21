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

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../utils/TxDataUtils.sol";
import "../interfaces/guards/IGuard.sol";
import "../interfaces/aave/IAaveProtocolDataProvider.sol";
import "../interfaces/IPoolManagerLogic.sol";
import "../interfaces/IHasGuardInfo.sol";
import "../interfaces/IManaged.sol";
import "../interfaces/IHasSupportedAsset.sol";

/// @title Transaction guard for Aave's incentives controller contract
contract AaveIncentivesControllerGuard is TxDataUtils, IGuard {
  using SafeMathUpgradeable for uint256;

  event ClaimRewards(address fundAddress, address aaveIncentivesController, uint256 amount, uint256 time);

  address public rewardToken;

  constructor(address _rewardToken) {
    rewardToken = _rewardToken;
  }

  /// @notice Transaction guard for Aave incentives controller
  /// @dev It supports claimRewards functionality
  /// @param _poolManagerLogic the pool manager logic
  /// @param data the transaction data
  /// @return txType the transaction type of a given transaction data. 2 for `Exchange` type
  function txGuard(
    address _poolManagerLogic,
    address to, // to
    bytes calldata data
  )
    external
    override
    returns (
      uint16 txType // transaction type
    )
  {
    bytes4 method = getMethod(data);
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();

    if (method == bytes4(keccak256("claimRewards(address[],uint256,address)"))) {
      uint256 amount = uint256(getInput(data, 1));
      address onBehalfOf = convert32toAddress(getInput(data, 2));

      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(rewardToken), "unsupported reward asset");
      require(onBehalfOf == poolLogic, "recipient is not pool");

      emit ClaimRewards(poolLogic, to, amount, block.timestamp);

      txType = 7; // `Claim` type
      return txType;
    }
  }
}
