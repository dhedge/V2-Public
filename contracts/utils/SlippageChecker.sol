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

import "../interfaces/IERC20Extended.sol";
import "../interfaces/IPoolManagerLogic.sol";
import "../interfaces/IHasSupportedAsset.sol";
import "../interfaces/IHasAssetInfo.sol";

/// @notice abstract contract for slippage check
abstract contract SlippageChecker is Ownable {
  using SafeMathUpgradeable for uint256;

  uint256 public slippageLimitNumerator;
  uint256 public slippageLimitDenominator;

  constructor(uint256 _slippageLimitNumerator, uint256 _slippageLimitDenominator) Ownable() {
    slippageLimitNumerator = _slippageLimitNumerator;
    slippageLimitDenominator = _slippageLimitDenominator;
  }

  /// @notice Update slippage limit numerator/denominator
  /// @param _slippageLimitNumerator slippage limit numerator - slippage limit would be numerator/denominator
  /// @param _slippageLimitDenominator slippage limit denominiator - slippage limit would be numerator/denominator
  function setSlippageLimit(uint256 _slippageLimitNumerator, uint256 _slippageLimitDenominator) external onlyOwner {
    slippageLimitNumerator = _slippageLimitNumerator;
    slippageLimitDenominator = _slippageLimitDenominator;
  }

  /// @notice Check slippage limit when swap tokens
  /// @param srcAsset the source asset address
  /// @param dstAsset the destination asset address
  /// @param srcAmount the source asset amount
  /// @param dstAmount the destination asset amount
  /// @param poolManagerLogic the pool manager logic address
  function _checkSlippageLimit(
    address srcAsset,
    address dstAsset,
    uint256 srcAmount,
    uint256 dstAmount,
    address poolManagerLogic
  ) internal view {
    if (IHasSupportedAsset(poolManagerLogic).isSupportedAsset(srcAsset)) {
      uint256 srcDecimals = IERC20Extended(srcAsset).decimals();
      uint256 dstDecimals = IERC20Extended(dstAsset).decimals();
      address poolFactory = IPoolManagerLogic(poolManagerLogic).factory();
      uint256 srcPrice = IHasAssetInfo(poolFactory).getAssetPrice(srcAsset);
      uint256 dstPrice = IHasAssetInfo(poolFactory).getAssetPrice(dstAsset);

      srcAmount = srcAmount.mul(srcPrice).div(10**srcDecimals); // to USD amount
      dstAmount = dstAmount.mul(dstPrice).div(10**dstDecimals); // to USD amount

      require(
        dstAmount.mul(slippageLimitDenominator).div(srcAmount) >= slippageLimitDenominator.sub(slippageLimitNumerator),
        "slippage limit exceed"
      );
    }
  }
}
