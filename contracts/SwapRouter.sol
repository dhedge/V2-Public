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
pragma abicoder v2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./interfaces/curve/ICurveCryptoSwap.sol";
import "./interfaces/uniswapv2/IUniswapV2Router.sol";
import "./interfaces/uniswapv2/IUniswapV2RouterSwapOnly.sol";

contract SwapRouter is Ownable, IUniswapV2RouterSwapOnly {
  using SafeERC20 for IERC20;

  struct CurvePoolCoin {
    address curvePool;
    address token;
    uint256 coinId;
  }

  IUniswapV2Router[] public uniV2Routers;
  ICurveCryptoSwap[] public curvePools;

  // Curve can get the token address from coinId, but not the other way around. Hence this mapping is required from token -> coinId
  mapping(address => mapping(address => uint256)) public curvePoolCoin;

  constructor(IUniswapV2Router[] memory _uniV2Routers, ICurveCryptoSwap[] memory _curvePools) Ownable() {
    uniV2Routers = _uniV2Routers;
    curvePools = _curvePools;
  }

  // ========== MUTATIVE FUNCTIONS ==========

  // ---------- Owner Functions ---------- //

  function setCurvePoolCoins(CurvePoolCoin[] calldata _curvePoolCoins) external onlyOwner {
    for (uint256 i = 0; i < _curvePoolCoins.length; i++) {
      setCurvePoolCoin(_curvePoolCoins[i]);
    }
  }

  function setCurvePoolCoin(CurvePoolCoin calldata _curvePoolCoin) public onlyOwner {
    curvePoolCoin[_curvePoolCoin.curvePool][_curvePoolCoin.token] = _curvePoolCoin.coinId;
  }

  // ---------- Public Functions ---------- //

  function swapExactTokensForTokens(
    uint256 amountIn,
    uint256 amountOutMin,
    address[] calldata path,
    address to,
    uint256 deadline
  ) external override returns (uint256[] memory amounts) {
    (uint256 uniV2RouterIndex, uint256 uniV2BestAmountOut) = getBestAmountOutUniV2Router(amountIn, path);

    (uint256 curvePoolIndex, uint256 curveBestAmountOut) = getBestAmountOutCurvePool(amountIn, path);

    IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
    IERC20(path[0]).approve(address(uniV2Routers[uniV2RouterIndex]), amountIn);

    if (uniV2BestAmountOut > curveBestAmountOut) {
      require(uniV2BestAmountOut > 0, "SwapRouter: invalid routing 01"); // invalid routing with Uni v2 swapExactTokensForTokens
      amounts = uniV2Routers[uniV2RouterIndex].swapExactTokensForTokens(amountIn, amountOutMin, path, to, deadline);
    } else {
      require(curveBestAmountOut > 0, "SwapRouter: invalid routing 03"); // invalid routing with Curve swapExactTokensForToken
      _curveExchange(curvePoolIndex, amountIn, amountOutMin, path);
      amounts[0] = amountIn;
      amounts[1] = curveBestAmountOut;
    }
  }

  function getCoin(uint256 curvePoolIndex, address token) public view returns (uint256 coin) {
    coin = curvePoolCoin[address(curvePools[curvePoolIndex])][token];
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
    require(bestAmountIn < uint256(-1), "SwapRouter: invalid routing 021"); // invalid routing with Uni v2 swapTokensForExactTokens

    IERC20(path[0]).transferFrom(msg.sender, address(this), bestAmountIn);
    IERC20(path[0]).approve(address(uniV2Routers[routerIndex]), bestAmountIn);
    amounts = uniV2Routers[routerIndex].swapTokensForExactTokens(amountOut, amountInMax, path, to, deadline);
  }

  // ---------- Internal Functions ---------- //

  function _curveExchange(
    uint256 curvePoolIndex,
    uint256 amountIn,
    uint256 amountOutMin,
    address[] calldata path
  ) internal {
    uint256 from = getCoin(curvePoolIndex, path[0]);
    uint256 to = getCoin(curvePoolIndex, path[path.length - 1]);
    curvePools[curvePoolIndex].exchange_underlying(from, to, amountIn, amountOutMin);
  }

  // ========== VIEWS ==========

  function getBestAmountOutUniV2Router(uint256 amountIn, address[] memory path)
    public
    view
    returns (uint256 routerIndex, uint256 bestAmountOut)
  {
    for (uint256 i = 0; i < uniV2Routers.length; i++) {
      uint256 amount = getAmountOutUniV2(uniV2Routers[i], amountIn, path);

      if (amount > bestAmountOut) {
        bestAmountOut = amount;
        routerIndex = i;
      }
    }
  }

  function getAmountOutUniV2(
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
      uint256 amount = getAmountInUniV2(uniV2Routers[i], amountOut, path);

      if (amount < bestAmountIn && amount > 0) {
        bestAmountIn = amount;
        routerIndex = i;
      }
    }
  }

  function getAmountInUniV2(
    IUniswapV2Router uniV2Router,
    uint256 amountOut,
    address[] memory path
  ) public view returns (uint256 amount) {
    uint256[] memory amounts = new uint256[](path.length);
    amounts = uniV2Router.getAmountsIn(amountOut, path);
    return amounts[0];
  }

  function getBestAmountOutCurvePool(uint256 amountIn, address[] memory path)
    public
    view
    returns (uint256 poolIndex, uint256 bestAmountOut)
  {
    for (uint256 i = 0; i < curvePools.length; i++) {
      uint256 amount = getAmountOutCurve(curvePools[i], amountIn, path);

      if (amount > bestAmountOut) {
        bestAmountOut = amount;
        poolIndex = i;
      }
    }
  }

  function getAmountOutCurve(
    ICurveCryptoSwap curvePool,
    uint256 amountIn,
    address[] memory path
  ) public view returns (uint256 amount) {
    uint256 from = curvePoolCoin[address(curvePool)][path[0]];
    uint256 to = curvePoolCoin[address(curvePool)][path[path.length - 1]];

    // Check that the coin mapping matches Curve for correct routing (especially if coinId = 0, which means it might not be set)
    if (curvePool.underlying_coins(from) != path[0]) {
      return 0; // CoinId doesn't match Curve setting. Don't use Curve.
    }

    if (curvePool.underlying_coins(from) != path[path.length - 1]) {
      return 0; // CoinId doesn't match Curve setting. Don't use Curve.
    }

    amount = curvePool.get_dy_underlying(from, to, amountIn);
  }
}
