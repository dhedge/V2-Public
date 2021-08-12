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

import "../utils/TxDataUtils.sol";
import "../interfaces/guards/IGuard.sol";
import "../interfaces/uniswapv2/IUniswapV2Factory.sol";
import "../interfaces/uniswapv2/IUniswapV2Router.sol";
import "../interfaces/IERC20Extended.sol";
import "../interfaces/IPoolManagerLogic.sol";
import "../interfaces/IHasSupportedAsset.sol";
import "../interfaces/IHasAssetInfo.sol";
import "../interfaces/IHasGuardInfo.sol";
import "../interfaces/IManaged.sol";

/// @notice Transaction guard for UniswapV2Router
/// @dev This will be used for sushiswap as well since Sushi uses the same interface.
contract UniswapV2RouterGuard is TxDataUtils, IGuard {
  using SafeMathUpgradeable for uint256;

  event ExchangeTo(address fundAddress, address sourceAsset, address dstAsset, uint256 dstAmount, uint256 time);
  event AddLiquidity(
    address fundAddress,
    address tokenA,
    address tokenB,
    address pair,
    uint256 amountADesired,
    uint256 amountBDesired,
    uint256 amountAMin,
    uint256 amountBMin,
    uint256 time
  );

  event RemoveLiquidity(
    address fundAddress,
    address tokenA,
    address tokenB,
    address pair,
    uint256 liquidity,
    uint256 amountAMin,
    uint256 amountBMin,
    uint256 time
  );

  uint256 public slippageLimitNumerator;
  uint256 public slippageLimitDenominator;

  constructor(uint256 _slippageLimitNumerator, uint256 _slippageLimitDenominator) {
    slippageLimitNumerator = _slippageLimitNumerator;
    slippageLimitDenominator = _slippageLimitDenominator;
  }

  /// @notice Transaction guard for Uniswap V2
  /// @dev It supports exchange, addLiquidity and removeLiquidity functionalities
  /// @param _poolManagerLogic the pool manager logic
  /// @param to the router address
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
    IPoolManagerLogic poolManagerLogic = IPoolManagerLogic(_poolManagerLogic);
    IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(_poolManagerLogic);

    bytes4 method = getMethod(data);

    if (method == bytes4(keccak256("swapExactTokensForTokens(uint256,uint256,address[],address,uint256)"))) {
      address srcAsset = convert32toAddress(getArrayIndex(data, 2, 0)); // gets the second input (path) first item (token to swap from)
      address dstAsset = convert32toAddress(getArrayLast(data, 2)); // gets second input (path) last item (token to swap to)
      uint256 srcAmount = uint256(getInput(data, 0));
      address toAddress = convert32toAddress(getInput(data, 3));
      uint256 routeLength = getArrayLength(data, 2); // length of the routing addresses
      address[] memory path = new address[](routeLength);
      for (uint8 i = 0; i < routeLength; i++) {
        path[i] = convert32toAddress(getArrayIndex(data, 2, i));
      }

      require(poolManagerLogicAssets.isSupportedAsset(dstAsset), "unsupported destination asset");

      require(poolManagerLogic.poolLogic() == toAddress, "recipient is not pool");

      _checkSlippageLimit(to, srcAmount, 0, path, address(poolManagerLogic));

      emit ExchangeFrom(poolManagerLogic.poolLogic(), srcAsset, uint256(srcAmount), dstAsset, block.timestamp);

      txType = 2; // 'Exchange' type
    } else if (method == bytes4(keccak256("swapTokensForExactTokens(uint256,uint256,address[],address,uint256)"))) {
      address srcAsset = convert32toAddress(getArrayIndex(data, 2, 0)); // gets the second input (path) first item (token to swap from)
      address dstAsset = convert32toAddress(getArrayLast(data, 2)); // gets second input (path) last item (token to swap to)
      uint256 dstAmount = uint256(getInput(data, 0));
      address toAddress = convert32toAddress(getInput(data, 3));
      uint256 routeLength = getArrayLength(data, 2); // length of the routing addresses
      address[] memory path = new address[](routeLength);
      for (uint8 i = 0; i < routeLength; i++) {
        path[i] = convert32toAddress(getArrayIndex(data, 2, i));
      }

      require(poolManagerLogicAssets.isSupportedAsset(dstAsset), "unsupported destination asset");

      require(poolManagerLogic.poolLogic() == toAddress, "recipient is not pool");

      _checkSlippageLimit(to, 0, dstAmount, path, address(poolManagerLogic));

      emit ExchangeTo(poolManagerLogic.poolLogic(), srcAsset, dstAsset, uint256(dstAmount), block.timestamp);

      txType = 2; // 'Exchange' type
    } else if (
      method == bytes4(keccak256("addLiquidity(address,address,uint256,uint256,uint256,uint256,address,uint256)"))
    ) {
      address tokenA = convert32toAddress(getInput(data, 0));
      address tokenB = convert32toAddress(getInput(data, 1));

      uint256 amountADesired = uint256(getInput(data, 2));
      uint256 amountBDesired = uint256(getInput(data, 3));
      uint256 amountAMin = uint256(getInput(data, 4));
      uint256 amountBMin = uint256(getInput(data, 5));

      require(poolManagerLogicAssets.isSupportedAsset(tokenA), "unsupported asset: tokenA");
      require(poolManagerLogicAssets.isSupportedAsset(tokenB), "unsupported asset: tokenB");

      address pair = IUniswapV2Factory(IUniswapV2Router(to).factory()).getPair(tokenA, tokenB);
      require(poolManagerLogicAssets.isSupportedAsset(pair), "unsupported lp asset");

      require(poolManagerLogic.poolLogic() == convert32toAddress(getInput(data, 6)), "recipient is not pool");

      emit AddLiquidity(
        poolManagerLogic.poolLogic(),
        tokenA,
        tokenB,
        pair,
        amountADesired,
        amountBDesired,
        amountAMin,
        amountBMin,
        block.timestamp
      );

      txType = 3; // `Add Liquidity` type
    } else if (
      method == bytes4(keccak256("removeLiquidity(address,address,uint256,uint256,uint256,address,uint256)"))
    ) {
      address tokenA = convert32toAddress(getInput(data, 0));
      address tokenB = convert32toAddress(getInput(data, 1));

      uint256 liquidity = uint256(getInput(data, 2));

      uint256 amountAMin = uint256(getInput(data, 3));
      uint256 amountBMin = uint256(getInput(data, 4));

      require(poolManagerLogicAssets.isSupportedAsset(tokenA), "unsupported asset: tokenA");
      require(poolManagerLogicAssets.isSupportedAsset(tokenB), "unsupported asset: tokenB");

      address pair = IUniswapV2Factory(IUniswapV2Router(to).factory()).getPair(tokenA, tokenB);
      require(poolManagerLogicAssets.isSupportedAsset(pair), "unsupported lp asset");

      require(poolManagerLogic.poolLogic() == convert32toAddress(getInput(data, 5)), "recipient is not pool");

      emit RemoveLiquidity(
        poolManagerLogic.poolLogic(),
        tokenA,
        tokenB,
        pair,
        liquidity,
        amountAMin,
        amountBMin,
        block.timestamp
      );

      txType = 4; // `Remove Liquidity` type
    }

    return (txType, false);
  }

  /// @notice Update slippage limit numerator/denominator
  /// @param _slippageLimitNumerator slippage limit numerator - slippage limit would be numerator/denominator
  /// @param _slippageLimitDenominator slippage limit denominiator - slippage limit would be numerator/denominator
  function setSlippageLimit(uint256 _slippageLimitNumerator, uint256 _slippageLimitDenominator) external {
    slippageLimitNumerator = _slippageLimitNumerator;
    slippageLimitDenominator = _slippageLimitDenominator;
  }

  /// @notice Check slippage limit when swap tokens
  /// @param router the uniswap V2 router address
  /// @param srcAmount the source asset amount
  /// @param dstAmount the destination asset amount
  /// @param path the swap path
  /// @param poolManagerLogic the pool manager logic address
  function _checkSlippageLimit(
    address router,
    uint256 srcAmount,
    uint256 dstAmount,
    address[] memory path,
    address poolManagerLogic
  ) internal view {
    address srcAsset = path[0];
    address dstAsset = path[path.length - 1];
    if (IHasSupportedAsset(poolManagerLogic).isSupportedAsset(srcAsset)) {
      uint256[] memory amounts;
      if (dstAmount == 0) {
        amounts = IUniswapV2Router(router).getAmountsOut(srcAmount, path);
        dstAmount = amounts[amounts.length - 1];
      } else if (srcAmount == 0) {
        amounts = IUniswapV2Router(router).getAmountsIn(dstAmount, path);
        srcAmount = amounts[0];
      }

      uint256 srcDecimals = IERC20Extended(srcAsset).decimals();
      uint256 dstDecimals = IERC20Extended(dstAsset).decimals();
      address poolFactory = IPoolManagerLogic(poolManagerLogic).factory();
      uint256 srcPrice = IHasAssetInfo(poolFactory).getAssetPrice(srcAsset);
      uint256 dstPrice = IHasAssetInfo(poolFactory).getAssetPrice(dstAsset);

      srcAmount = srcAmount.mul(srcPrice).div(10**srcDecimals); // to USD amount
      dstAmount = dstAmount.mul(dstPrice).div(10**dstDecimals); // to USD amount

      require(
        dstAmount.mul(slippageLimitDenominator).div(srcAmount) >=
          slippageLimitDenominator.sub(slippageLimitNumerator) &&
          dstAmount.mul(slippageLimitDenominator).div(srcAmount) <=
          slippageLimitDenominator.add(slippageLimitNumerator),
        "slippage limit exceed"
      );
    }
  }
}
