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

import "../interfaces/IUniswapV2Router.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title A library for tokens exchange.
 * @dev Swap tokens using sushiswap router
 */
library DhedgeSwap {
  /**
   * @notice Swap tokens via sushiswap router
   */
  function swapTokensIn(
    IUniswapV2Router swapRouter,
    address weth,
    address from,
    address to,
    uint256 amountIn
  ) internal {
    if (from == to) {
      return;
    }

    address[] memory path;
    if (from == weth || to == weth) {
      path = new address[](2);
      path[0] = from;
      path[1] = to;
    } else {
      path = new address[](3);
      path[0] = from;
      path[1] = weth;
      path[2] = to;
    }

    // Approve if not enough swap allowance
    if (IERC20(from).allowance(address(this), address(swapRouter)) < amountIn) {
      IERC20(from).approve(address(swapRouter), amountIn);
    }

    swapRouter.swapExactTokensForTokens(amountIn, 0, path, address(this), uint256(-1));
  }

  /**
   * @notice Swap tokens via sushiswap router
   */
  function swapTokensOut(
    IUniswapV2Router swapRouter,
    address weth,
    address from,
    address to,
    uint256 amountOut
  ) internal {
    if (from == to) {
      return;
    }

    address[] memory path;
    if (from == weth || to == weth) {
      path = new address[](2);
      path[0] = from;
      path[1] = to;
    } else {
      path = new address[](3);
      path[0] = from;
      path[1] = weth;
      path[2] = to;
    }

    // Approve if not enough swap allowance
    bool approved;
    uint256 fromBalance = IERC20(from).balanceOf(address(this));
    if (IERC20(from).allowance(address(this), address(swapRouter)) < fromBalance) {
      IERC20(from).approve(address(swapRouter), fromBalance);
      approved = true;
    }

    swapRouter.swapTokensForExactTokens(amountOut, fromBalance, path, address(this), uint256(-1));

    // Only remove swap allowance if approved by this function
    // So that manager will not have to approve again
    if (approved) {
      IERC20(from).approve(address(swapRouter), 0);
    }
  }
}
