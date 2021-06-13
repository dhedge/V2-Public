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
// Copyright (c) 2020 dHEDGE DAO
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

pragma solidity 0.7.6;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

import "./IGuard.sol";
import "../utils/TxDataUtils.sol";
import "../interfaces/IUniswapV2Factory.sol";
import "../interfaces/IPoolManagerLogic.sol";
import "../interfaces/IHasSupportedAsset.sol";
import "../interfaces/IHasGuardInfo.sol";
import "../interfaces/IManaged.sol";
import "../interfaces/IHasSupportedAsset.sol";

/**
 * @notice Transaction guard for UniswapV2Router
 * @dev This will be used for sushiswap as well since Sushi uses the same interface.
 */
contract UniswapV2RouterGuard is TxDataUtils, IGuard {
  using SafeMathUpgradeable for uint256;

  event AddLiquidity(address fundAddress, address tokenA, address tokenB, address pair, uint256 time);
  event RemoveLiquidity(
    address fundAddress,
    address tokenA,
    address tokenB,
    address pair,
    uint256 liquidity,
    uint256 time
  );

  address public factory; // uniswap v2 factory

  constructor(address _factory) public {
    factory = _factory;
  }

  /**
   * @notice Transaction guard for Uniswap V2
   * @dev It supports exchange, addLiquidity and removeLiquidity functionalities
   * @param _poolManagerLogic the pool manager logic
   * @param data the transaction data
   * @return txType the transaction type of a given transaction data. 2 for `Exchange` type, 3 for `Add Liquidity`, 4 for `Remove Liquidity`
   */
  function txGuard(address _poolManagerLogic, bytes calldata data)
    external
    override
    returns (
      uint8 txType // transaction type
    )
  {
    bytes4 method = getMethod(data);

    if (method == bytes4(keccak256("swapExactTokensForTokens(uint256,uint256,address[],address,uint256)"))) {
      address srcAsset = convert32toAddress(getArrayIndex(data, 2, 0)); // gets the second input (path) first item (token to swap from)
      address dstAsset = convert32toAddress(getArrayLast(data, 2)); // gets second input (path) last item (token to swap to)
      uint256 srcAmount = uint256(getInput(data, 0));
      address toAddress = convert32toAddress(getInput(data, 3));
      uint256 routeLength = getArrayLength(data, 2); // length of the routing addresses

      IPoolManagerLogic poolManagerLogic = IPoolManagerLogic(_poolManagerLogic);
      IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(_poolManagerLogic);
      require(poolManagerLogicAssets.isSupportedAsset(srcAsset), "unsupported source asset");

      // validate Uniswap routing addresses
      for (uint8 i = 1; i < routeLength - 1; i++) {
        require(poolManagerLogic.validateAsset(convert32toAddress(getArrayIndex(data, 2, i))), "invalid routing asset");
      }

      require(poolManagerLogicAssets.isSupportedAsset(dstAsset), "unsupported destination asset");

      require(poolManagerLogic.poolLogic() == toAddress, "recipient is not pool");

      emit Exchange(poolManagerLogic.poolLogic(), srcAsset, uint256(srcAmount), dstAsset, block.timestamp);

      txType = 2; // 'Exchange' type
    } else if (
      method == bytes4(keccak256("addLiquidity(address,address,uint256,uint256,uint256,uint256,address,uint256)"))
    ) {
      IPoolManagerLogic poolManagerLogic = IPoolManagerLogic(_poolManagerLogic);

      address tokenA = convert32toAddress(getInput(data, 0));
      address tokenB = convert32toAddress(getInput(data, 1));

      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(tokenA), "unsupported asset: tokenA");
      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(tokenB), "unsupported asset: tokenB");

      address pair = IUniswapV2Factory(factory).getPair(tokenA, tokenB);
      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(pair), "unsupported lp asset");

      address to = convert32toAddress(getInput(data, 6));
      require(poolManagerLogic.poolLogic() == to, "recipient is not pool");

      emit AddLiquidity(poolManagerLogic.poolLogic(), tokenA, tokenB, pair, block.timestamp);

      txType = 3; // `Add Liquidity` type
    } else if (
      method == bytes4(keccak256("removeLiquidity(address,address,uint256,uint256,uint256,address,uint256)"))
    ) {
      IPoolManagerLogic poolManagerLogic = IPoolManagerLogic(_poolManagerLogic);

      address tokenA = convert32toAddress(getInput(data, 0));
      address tokenB = convert32toAddress(getInput(data, 1));

      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(tokenA), "unsupported asset: tokenA");
      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(tokenB), "unsupported asset: tokenB");

      address pair = IUniswapV2Factory(factory).getPair(tokenA, tokenB);
      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(pair), "unsupported lp asset");

      address to = convert32toAddress(getInput(data, 5));
      require(poolManagerLogic.poolLogic() == to, "recipient is not pool");

      uint256 liquidity = uint256(getInput(data, 2));

      emit RemoveLiquidity(poolManagerLogic.poolLogic(), tokenA, tokenB, pair, liquidity, block.timestamp);

      txType = 4; // `Remove Liquidity` type
    }
  }
}
