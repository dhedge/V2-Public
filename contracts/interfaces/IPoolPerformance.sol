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

import "./IHasSupportedAsset.sol";

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

interface IPoolPerformance {
  function changeAssetBalance(
    address asset,
    uint256 plusAmount,
    uint256 minusAmount
  ) external;

  function hasExternalBalances(address poolAddress) external view returns (bool);

  function updateInternalBalances() external;

  function getBalancesSnapshot(address poolManagerAddress, IHasSupportedAsset.Asset[] memory supportedAssets)
    external
    view
    returns (uint256[] memory supportedAssetBalances);

  function updatedInternalBalancesByDiff(
    IHasSupportedAsset.Asset[] memory supportedAssets,
    uint256[] memory beforeSupportedAssetBalances,
    uint256[] memory afterSupportedAssetBalances
  ) external;

  function recordExternalValue(address poolAddress) external;

  function adjustInternalValueFactor(uint256 a, uint256 b) external;

  function resetInternalValueFactor() external;

  function initializePool() external;

  function tokenPriceAdjustedForManagerFee(address poolAddress) external view returns (uint256);
}
