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

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../utils/TxDataUtils.sol";
import "../utils/SlippageChecker.sol";
import "../interfaces/guards/IGuard.sol";
import "../interfaces/IPoolManagerLogic.sol";
import "../interfaces/IHasSupportedAsset.sol";

/// @notice Transaction guard for OneInchV3Router
contract OneInchV3Guard is TxDataUtils, SlippageChecker, IGuard {
  constructor(uint256 _slippageLimitNumerator, uint256 _slippageLimitDenominator)
    SlippageChecker(_slippageLimitNumerator, _slippageLimitDenominator)
  {}

  /// @notice Transaction guard for OneInchV3
  /// @dev It supports swap functionalities
  /// @param _poolManagerLogic the pool manager logic
  /// @param data the transaction data
  /// @return txType the transaction type of a given transaction data. 2 for `Exchange` type
  /// @return isPublic if the transaction is public or private
  function txGuard(
    address _poolManagerLogic,
    address, // to
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

    if (method == 0x7c025200) {
      // 1inch's `swap` method
      address srcAsset = convert32toAddress(getInput(data, 3));
      address dstAsset = convert32toAddress(getInput(data, 4));
      uint256 srcAmount = uint256(getInput(data, 7));
      uint256 amountOutMin = uint256(getInput(data, 8));

      require(poolManagerLogicAssets.isSupportedAsset(dstAsset), "unsupported destination asset");

      _checkSlippageLimit(srcAsset, dstAsset, srcAmount, amountOutMin, address(poolManagerLogic));

      emit ExchangeFrom(poolManagerLogic.poolLogic(), srcAsset, uint256(srcAmount), dstAsset, block.timestamp);

      txType = 2; // 'Exchange' type
    } else if (method == 0x2e95b6c8) {
      // 1inch's `unoswap` method
      address srcAsset = convert32toAddress(getInput(data, 0));
      uint256 srcAmount = uint256(getInput(data, 1));
      uint256 amountOutMin = uint256(getInput(data, 2));
      address dstAsset = convert32toAddress(getArrayLast(data, 3));

      require(poolManagerLogicAssets.isSupportedAsset(dstAsset), "unsupported destination asset");

      _checkSlippageLimit(srcAsset, dstAsset, srcAmount, amountOutMin, address(poolManagerLogic));

      emit ExchangeFrom(poolManagerLogic.poolLogic(), srcAsset, uint256(srcAmount), dstAsset, block.timestamp);
    }

    return (txType, false);
  }
}
