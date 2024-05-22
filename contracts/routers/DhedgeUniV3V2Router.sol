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
// Copyright (c) 2022 dHEDGE DAO
//
// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

import "../interfaces/curve/ICurveCryptoSwap.sol";
import "../interfaces/uniswapV3/IV3SwapRouter.sol";
import "../interfaces/uniswapV2/IUniswapV2Router.sol";
import "../interfaces/uniswapV2/IUniswapV2RouterSwapOnly.sol";
import "../utils/uniswap/UniswapV3QuoterLibrary.sol";

contract DhedgeUniV3V2Router is IUniswapV2RouterSwapOnly {
  using SafeERC20 for IERC20;
  using SafeMath for uint256;
  using UniswapV3QuoterLibrary for IUniswapV3Factory;

  IUniswapV3Factory public uniV3Factory;
  IV3SwapRouter public uniV3Router;

  uint24[] public poolFees;

  constructor(IUniswapV3Factory _uniV3Factory, IV3SwapRouter _uniV3Router) {
    uniV3Factory = _uniV3Factory;
    uniV3Router = _uniV3Router;

    // Uniswap liquidity pools fee tiers we loop through to obtain best swap quote
    poolFees.push(100); // 0.01%
    poolFees.push(500); // 0.05%
    poolFees.push(3000); // 0.3%
    // poolFees.push(10000); // 1%
  }

  // ---------- Public Functions ---------- //

  function swapExactTokensForTokens(
    uint256 amountIn,
    uint256 amountOutMin,
    address[] calldata path,
    address to,
    uint256
  ) external override returns (uint256[] memory amountsOut) {
    bytes memory swapPath;
    (amountsOut, swapPath) = _getAmountsOut(amountIn, path);
    // solhint-disable-next-line reason-string
    require(amountsOut[path.length - 1] >= amountOutMin);

    IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);

    IV3SwapRouter.ExactInputParams memory params;
    params.recipient = to;
    params.amountIn = amountIn;
    params.amountOutMinimum = amountOutMin;
    params.path = swapPath;

    IERC20(path[0]).approve(address(uniV3Router), amountIn);
    uint256 amountOut = uniV3Router.exactInput(params);

    // The UniswapV3QuoterLibrary only provides an estimate. In some cases the amount the quote returns and the amount you get post swap differ marginally
    // This means if the actual swap returns less than the quote but more than the amountOutMin we let it slide.
    require(amountOut >= amountOutMin, "too much slippage");
  }

  function swapTokensForExactTokens(
    uint256 expectedAmountOut,
    uint256 amountInMax,
    address[] calldata path,
    address to,
    uint256
  ) external override returns (uint256[] memory amountsIn) {
    bytes memory swapPath;
    (amountsIn, swapPath) = _getAmountsIn(expectedAmountOut, path);
    // solhint-disable-next-line reason-string
    require(amountsIn[0] <= amountInMax);

    IERC20(path[0]).transferFrom(msg.sender, address(this), amountsIn[0]);

    IV3SwapRouter.ExactOutputParams memory params;
    params.recipient = to;
    params.amountOut = expectedAmountOut;
    params.amountInMaximum = amountsIn[0];
    params.path = swapPath;

    IERC20(path[0]).approve(address(uniV3Router), amountsIn[0]);
    uint256 amountIn = uniV3Router.exactOutput(params);

    require(amountIn <= amountInMax, "too much slippage");
  }

  function getAmountsOut(
    uint256 amountIn,
    address[] calldata path
  ) external view override returns (uint256[] memory amountsOut) {
    (amountsOut, ) = _getAmountsOut(amountIn, path);
  }

  function _getAmountsOut(
    uint256 amountIn,
    address[] calldata path
  ) internal view returns (uint256[] memory amountsOut, bytes memory swapPath) {
    amountsOut = new uint256[](path.length);
    amountsOut[0] = amountIn;
    swapPath = abi.encodePacked(path[0]);

    for (uint256 i = 1; i < path.length; i++) {
      uint256 bestAmountOut;
      uint24 bestPoolFee;
      for (uint256 j = 0; j < poolFees.length; j++) {
        uint24 poolFee = poolFees[j];
        if (uniV3Factory.getPool(path[i], path[i - 1], poolFee) != address(0)) {
          uint256 amountOut = uniV3Factory.estimateMaxSwapUniswapV3(path[i - 1], path[i], amountsOut[i - 1], poolFee);
          if (amountOut != 0 && amountOut > bestAmountOut) {
            bestPoolFee = poolFee;
            bestAmountOut = amountOut;
          }
        }
      }

      if (bestAmountOut == 0) {
        break;
      }

      amountsOut[i] = bestAmountOut;
      swapPath = abi.encodePacked(swapPath, bestPoolFee, path[i]);
    }
  }

  function getAmountsIn(uint256 amountOut, address[] calldata path) external view returns (uint256[] memory amountsIn) {
    (amountsIn, ) = _getAmountsIn(amountOut, path);
  }

  function _getAmountsIn(
    uint256 amountOut,
    address[] calldata path
  ) internal view returns (uint256[] memory amountsIn, bytes memory swapPath) {
    amountsIn = new uint256[](path.length);
    amountsIn[path.length - 1] = amountOut;
    swapPath = abi.encodePacked(path[path.length - 1]);

    for (uint256 i = path.length - 1; i > 0; i--) {
      uint256 bestAmountIn = type(uint256).max;
      uint24 bestPoolFee;
      for (uint256 j = 0; j < poolFees.length; j++) {
        uint24 poolFee = poolFees[j];
        if (uniV3Factory.getPool(path[i], path[i - 1], poolFee) != address(0)) {
          uint256 amountIn = uniV3Factory.estimateMinSwapUniswapV3(path[i], path[i - 1], amountsIn[i], poolFee);
          uint256 amountTo = uniV3Factory.estimateMaxSwapUniswapV3(path[i - 1], path[i], amountIn, poolFee);
          if (amountIn != 0 && amountIn < bestAmountIn && amountTo >= amountsIn[i]) {
            bestAmountIn = amountIn;
            bestPoolFee = poolFee;
          }
        }
      }

      if (bestAmountIn == type(uint256).max) {
        break;
      }

      amountsIn[i - 1] = bestAmountIn;
      swapPath = abi.encodePacked(swapPath, bestPoolFee, path[i - 1]);
    }
  }
}
