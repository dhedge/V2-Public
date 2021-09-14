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

import "@openzeppelin/contracts-upgradeable/math/SignedSafeMathUpgradeable.sol";

import "../utils/TxDataUtils.sol";
import "../utils/SlippageChecker.sol";
import "../interfaces/guards/IGuard.sol";
import "../interfaces/IPoolManagerLogic.sol";
import "../interfaces/IHasSupportedAsset.sol";
import "../interfaces/balancer/IBalancerV2Vault.sol";

/// @notice Transaction guard for Balancer V2 Vault
contract BalancerV2Guard is TxDataUtils, SlippageChecker, IGuard {
  using SignedSafeMathUpgradeable for int256;

  constructor(uint256 _slippageLimitNumerator, uint256 _slippageLimitDenominator)
    SlippageChecker(_slippageLimitNumerator, _slippageLimitDenominator)
  {}

  /// @notice Transaction guard for Balancer V2 Vault
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

    if (method == IBalancerV2Vault.swap.selector) {
      uint256 swapkind = uint256(getArrayIndex(data, 0, 0));
      if (swapkind == uint256(IBalancerV2Vault.SwapKind.GIVEN_IN)) {
        address srcAsset = convert32toAddress(getArrayIndex(data, 0, 1));
        address dstAsset = convert32toAddress(getArrayIndex(data, 0, 2));
        address fromAddress = convert32toAddress(getInput(data, 1));
        address toAddress = convert32toAddress(getInput(data, 3));
        uint256 srcAmount = uint256(getArrayIndex(data, 0, 3));
        uint256 amountOutMin = uint256(getInput(data, 5));

        require(poolManagerLogicAssets.isSupportedAsset(dstAsset), "unsupported destination asset");

        require(poolManagerLogic.poolLogic() == fromAddress, "sender is not pool");
        require(poolManagerLogic.poolLogic() == toAddress, "recipient is not pool");

        _checkSlippageLimit(srcAsset, dstAsset, srcAmount, amountOutMin, address(poolManagerLogic));

        emit ExchangeFrom(poolManagerLogic.poolLogic(), srcAsset, uint256(srcAmount), dstAsset, block.timestamp);

        txType = 2; // 'Exchange' type
      } else if (swapkind == uint256(IBalancerV2Vault.SwapKind.GIVEN_OUT)) {
        address srcAsset = convert32toAddress(getArrayIndex(data, 0, 1));
        address dstAsset = convert32toAddress(getArrayIndex(data, 0, 2));
        address fromAddress = convert32toAddress(getInput(data, 1));
        address toAddress = convert32toAddress(getInput(data, 3));
        uint256 dstAmount = uint256(getArrayIndex(data, 0, 3));
        uint256 amountInMax = uint256(getInput(data, 5));

        require(poolManagerLogicAssets.isSupportedAsset(dstAsset), "unsupported destination asset");

        require(poolManagerLogic.poolLogic() == fromAddress, "sender is not pool");
        require(poolManagerLogic.poolLogic() == toAddress, "recipient is not pool");

        _checkSlippageLimit(srcAsset, dstAsset, amountInMax, dstAmount, address(poolManagerLogic));

        emit ExchangeTo(poolManagerLogic.poolLogic(), srcAsset, dstAsset, uint256(dstAmount), block.timestamp);

        txType = 2; // 'Exchange' type
      }
    } else if (method == IBalancerV2Vault.batchSwap.selector) {
      uint256 swapkind = uint256(getInput(data, 0));
      if (swapkind == uint256(IBalancerV2Vault.SwapKind.GIVEN_IN)) {
        address srcAsset = convert32toAddress(getArrayIndex(data, 2, 0));
        address dstAsset = convert32toAddress(getArrayLast(data, 2));
        address fromAddress = convert32toAddress(getInput(data, 3));
        address toAddress = convert32toAddress(getInput(data, 5));
        uint256 srcAmount = uint256(int256(getArrayIndex(data, 7, 0)));
        uint256 amountOutMin = uint256(int256(0).sub(int256(getArrayLast(data, 7))));

        require(poolManagerLogicAssets.isSupportedAsset(dstAsset), "unsupported destination asset");

        require(poolManagerLogic.poolLogic() == fromAddress, "sender is not pool");
        require(poolManagerLogic.poolLogic() == toAddress, "recipient is not pool");

        _checkSlippageLimit(srcAsset, dstAsset, srcAmount, amountOutMin, address(poolManagerLogic));

        emit ExchangeFrom(poolManagerLogic.poolLogic(), srcAsset, uint256(srcAmount), dstAsset, block.timestamp);

        txType = 2; // 'Exchange' type
      } else if (swapkind == uint256(IBalancerV2Vault.SwapKind.GIVEN_OUT)) {
        address srcAsset = convert32toAddress(getArrayIndex(data, 2, 0));
        address dstAsset = convert32toAddress(getArrayLast(data, 2));
        address fromAddress = convert32toAddress(getInput(data, 3));
        address toAddress = convert32toAddress(getInput(data, 5));
        uint256 amountInMax = uint256(int256(getArrayIndex(data, 7, 0)));
        uint256 dstAmount = uint256(int256(0).sub(int256(getArrayLast(data, 7))));

        require(poolManagerLogicAssets.isSupportedAsset(dstAsset), "unsupported destination asset");

        require(poolManagerLogic.poolLogic() == fromAddress, "sender is not pool");
        require(poolManagerLogic.poolLogic() == toAddress, "recipient is not pool");

        _checkSlippageLimit(srcAsset, dstAsset, amountInMax, dstAmount, address(poolManagerLogic));

        emit ExchangeTo(poolManagerLogic.poolLogic(), srcAsset, dstAsset, uint256(dstAmount), block.timestamp);

        txType = 2; // 'Exchange' type
      }
    }

    return (txType, false);
  }
}
