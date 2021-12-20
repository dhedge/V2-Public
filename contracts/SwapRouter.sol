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

pragma solidity 0.7.6;
// pragma abicoder v2;

import "./interfaces/uniswapv2/IUniswapV2Router.sol";
import "./interfaces/uniswapv2/IUniswapV2RouterSwapOnly.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SwapRouter is IUniswapV2RouterSwapOnly {
  using SafeERC20 for IERC20;

  IUniswapV2Router[] public uniV2Routers;

  constructor(IUniswapV2Router[] memory _uniV2Routers) {
    uniV2Routers = _uniV2Routers;
    // curveRouters = _curveRouters;
  }

  // ========== MUTATIVE FUNCTIONS ==========

  function swapExactTokensForTokens(
    uint256 amountIn,
    uint256 amountOutMin,
    address[] calldata path,
    address to,
    uint256 deadline
  ) external override returns (uint256[] memory amounts) {
    (uint256 routerIndex, uint256 bestAmountOut) = getBestAmountOutUniV2Router(amountIn, path);
    require(bestAmountOut > 2 * 10**15, "SwapRouter: invalid routing 01"); // invalid routing with Uni v2 swapExactTokensForTokens

    IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
    IERC20(path[0]).approve(address(uniV2Routers[routerIndex]), amountIn);
    amounts = uniV2Routers[routerIndex].swapExactTokensForTokens(amountIn, amountOutMin, path, to, deadline);
  }

  function swapTokensForExactTokens(
    uint256 amountOut,
    uint256 amountInMax,
    address[] calldata path,
    address to,
    uint256 deadline
  ) external override returns (uint256[] memory amounts) {
    (uint256 routerIndex, uint256 bestAmountIn) = getBestAmountInUniV2Router(amountOut, path);
    require(bestAmountIn > 0, "SwapRouter: invalid routing 02"); // invalid routing with Uni v2 swapTokensForExactTokens

    IERC20(path[0]).transferFrom(msg.sender, address(this), bestAmountIn);
    IERC20(path[0]).approve(address(uniV2Routers[routerIndex]), bestAmountIn);
    amounts = uniV2Routers[routerIndex].swapTokensForExactTokens(amountOut, amountInMax, path, to, deadline);
  }

  // ========== VIEWS ==========

  function getBestAmountOutUniV2Router(uint256 amountIn, address[] memory path)
    public
    view
    returns (uint256 routerIndex, uint256 bestAmountOut)
  {
    for (uint256 i = 0; i < uniV2Routers.length; i++) {
      uint256 amount = getAmountOut(uniV2Routers[i], amountIn, path);
      require(amount > 0, "Amount = 0");
      if (amount > bestAmountOut) {
        bestAmountOut = amount;
        routerIndex = i;
      }
    }
  }

  function getAmountOut(
    IUniswapV2Router uniV2Router,
    uint256 amountIn,
    address[] memory path
  ) public view returns (uint256 amount) {
    uint256[] memory amounts = new uint256[](path.length);
    amounts = uniV2Router.getAmountsOut(amountIn, path);
    return amounts[amounts.length - 1];
  }

  function getBestAmountInUniV2Router(uint256 amountOut, address[] memory path)
    public
    view
    returns (uint256 routerIndex, uint256 bestAmountIn)
  {
    bestAmountIn = uint256(-1); // first set to largest value to find lowest amountIn
    for (uint256 i = 0; i < uniV2Routers.length; i++) {
      uint256 amount = getAmountIn(uniV2Routers[i], amountOut, path);
      require(amount > 0, "Amount = 0");
      if (amount < bestAmountIn && amount > 0) {
        bestAmountIn = amount;
        routerIndex = i;
      }
    }
  }

  function getAmountIn(
    IUniswapV2Router uniV2Router,
    uint256 amountOut,
    address[] memory path
  ) public view returns (uint256 amount) {
    uint256[] memory amounts = new uint256[](path.length);
    amounts = uniV2Router.getAmountsIn(amountOut, path);
    return amounts[0];
  }
}
