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
import "@openzeppelin/contracts/access/Ownable.sol";

import "../../utils/TxDataUtils.sol";
import "../../utils/SlippageChecker.sol";
import "../../interfaces/guards/IGuard.sol";
import "../../interfaces/uniswapv2/IUniswapV2Pair.sol";
import "../../interfaces/uniswapv3/IUniswapV3Pool.sol";
import "../../interfaces/oneInch/IAggregationRouterV3.sol";
import "../../interfaces/IPoolManagerLogic.sol";
import "../../interfaces/IHasSupportedAsset.sol";

/// @notice Transaction guard for OneInchV3Router
contract OneInchV4Guard is TxDataUtils, SlippageChecker, IGuard {
  uint256 private constant _ONE_FOR_ZERO_MASK = 1 << 255;

  constructor(uint256 _slippageLimitNumerator, uint256 _slippageLimitDenominator)
    SlippageChecker(_slippageLimitNumerator, _slippageLimitDenominator)
  // solhint-disable-next-line no-empty-blocks
  {

  }

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

    if (
      method == bytes4(keccak256("swap(address,(address,address,address,address,uint256,uint256,uint256,bytes),bytes)"))
    ) {
      (, IAggregationRouterV3.SwapDescription memory desc, ) = abi.decode(
        getParams(data),
        (address, IAggregationRouterV3.SwapDescription, bytes)
      );

      address srcAsset = desc.srcToken;
      address dstAsset = desc.dstToken;
      address toAddress = desc.dstReceiver;
      uint256 srcAmount = desc.amount;
      uint256 amountOutMin = desc.minReturnAmount;

      require(poolManagerLogicAssets.isSupportedAsset(dstAsset), "unsupported destination asset");

      require(poolManagerLogic.poolLogic() == toAddress, "recipient is not pool");

      _checkSlippageLimit(srcAsset, dstAsset, srcAmount, amountOutMin, address(poolManagerLogic));

      emit ExchangeFrom(poolManagerLogic.poolLogic(), srcAsset, uint256(srcAmount), dstAsset, block.timestamp);

      txType = 2; // 'Exchange' type
    } else if (method == bytes4(keccak256("unoswap(address,uint256,uint256,bytes32[])"))) {
      (address srcAsset, uint256 srcAmount, uint256 amountOutMin, bytes32[] memory pools) = abi.decode(
        getParams(data),
        (address, uint256, uint256, bytes32[])
      );

      address dstAsset = srcAsset;
      uint256 poolLength = pools.length;
      for (uint8 i = 0; i < poolLength; i++) {
        address pool = convert32toAddress(pools[i]);
        address token0 = IUniswapV2Pair(pool).token0();
        address token1 = IUniswapV2Pair(pool).token1();
        if (dstAsset == token0) {
          dstAsset = token1;
        } else if (dstAsset == token1) {
          dstAsset = token0;
        } else {
          require(false, "invalid path");
        }
      }

      require(poolManagerLogicAssets.isSupportedAsset(dstAsset), "unsupported destination asset");

      _checkSlippageLimit(srcAsset, dstAsset, srcAmount, amountOutMin, address(poolManagerLogic));

      emit ExchangeFrom(poolManagerLogic.poolLogic(), srcAsset, uint256(srcAmount), dstAsset, block.timestamp);

      txType = 2; // 'Exchange' type
    } else if (method == bytes4(keccak256("uniswapV3Swap(uint256,uint256,uint256[])"))) {
      (uint256 srcAmount, uint256 amountOutMin, uint256[] memory pools) = abi.decode(
        getParams(data),
        (uint256, uint256, uint256[])
      );

      bool zeroForOne = pools[0] & _ONE_FOR_ZERO_MASK == 0;
      address srcAsset = zeroForOne ? IUniswapV3Pool(pools[0]).token0() : IUniswapV3Pool(pools[0]).token1();
      address dstAsset = srcAsset;
      for (uint8 i = 0; i < pools.length; i++) {
        address token0 = IUniswapV3Pool(pools[i]).token0();
        address token1 = IUniswapV3Pool(pools[i]).token1();
        if (dstAsset == token0) {
          dstAsset = token1;
        } else if (dstAsset == token1) {
          dstAsset = token0;
        } else {
          require(false, "invalid path");
        }
      }

      require(poolManagerLogicAssets.isSupportedAsset(dstAsset), "unsupported destination asset");

      _checkSlippageLimit(srcAsset, dstAsset, srcAmount, amountOutMin, address(poolManagerLogic));

      emit ExchangeFrom(poolManagerLogic.poolLogic(), srcAsset, uint256(srcAmount), dstAsset, block.timestamp);

      txType = 2; // 'Exchange' type
    } else if (method == bytes4(keccak256("uniswapV3SwapTo(address,uint256,uint256,uint256[])"))) {
      (address toAddress, uint256 srcAmount, uint256 amountOutMin, uint256[] memory pools) = abi.decode(
        getParams(data),
        (address, uint256, uint256, uint256[])
      );

      bool zeroForOne = pools[0] & _ONE_FOR_ZERO_MASK == 0;
      address srcAsset = zeroForOne ? IUniswapV3Pool(pools[0]).token0() : IUniswapV3Pool(pools[0]).token1();
      address dstAsset = srcAsset;
      for (uint8 i = 0; i < pools.length; i++) {
        address token0 = IUniswapV3Pool(pools[i]).token0();
        address token1 = IUniswapV3Pool(pools[i]).token1();
        if (dstAsset == token0) {
          dstAsset = token1;
        } else if (dstAsset == token1) {
          dstAsset = token0;
        } else {
          require(false, "invalid path");
        }
      }

      require(poolManagerLogicAssets.isSupportedAsset(dstAsset), "unsupported destination asset");

      require(poolManagerLogic.poolLogic() == toAddress, "recipient is not pool");

      _checkSlippageLimit(srcAsset, dstAsset, srcAmount, amountOutMin, address(poolManagerLogic));

      emit ExchangeFrom(poolManagerLogic.poolLogic(), srcAsset, uint256(srcAmount), dstAsset, block.timestamp);

      txType = 2; // 'Exchange' type
    }

    return (txType, false);
  }
}
