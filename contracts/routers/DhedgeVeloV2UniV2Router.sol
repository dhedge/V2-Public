// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/velodrome/IVelodromeV2Factory.sol";
import "../interfaces/velodrome/IVelodromeV2Router.sol";
import "../interfaces/velodrome/IVelodromeV2Pair.sol";
import "../interfaces/uniswapV2/IUniswapV2RouterSwapOnly.sol";

contract DhedgeVeloV2UniV2Router is IUniswapV2RouterSwapOnly {
  using SafeERC20 for IERC20;
  using SafeMath for uint256;

  uint256 private constant HOPS_LIMIT = 3;

  IVelodromeV2Router public velodromeV2Router;
  IVelodromeV2Factory public velodromeV2Factory;

  constructor(IVelodromeV2Router _velodromeV2Router, IVelodromeV2Factory _velodromeV2Factory) {
    velodromeV2Router = _velodromeV2Router;
    velodromeV2Factory = _velodromeV2Factory;
  }

  function swapExactTokensForTokens(
    uint256 amountIn,
    uint256 amountOutMin,
    address[] calldata path,
    address to,
    uint256 deadline
  ) external override returns (uint256[] memory amountsOut) {
    require(path.length <= HOPS_LIMIT, "too many hops");

    (uint256 out, bool stable) = _getAmountOut(path[0], path[1], amountIn);

    IVelodromeV2Router.Route[] memory routes = new IVelodromeV2Router.Route[](path.length == HOPS_LIMIT ? 2 : 1);
    routes[0] = IVelodromeV2Router.Route({
      from: path[0],
      to: path[1],
      stable: stable,
      factory: address(velodromeV2Factory)
    });
    if (path.length == HOPS_LIMIT) {
      (, stable) = _getAmountOut(path[1], path[2], out);
      routes[1] = IVelodromeV2Router.Route({
        from: path[1],
        to: path[2],
        stable: stable,
        factory: address(velodromeV2Factory)
      });
    }

    IERC20(path[0]).safeTransferFrom(msg.sender, address(this), amountIn);
    IERC20(path[0]).safeIncreaseAllowance(address(velodromeV2Router), amountIn);
    amountsOut = velodromeV2Router.swapExactTokensForTokens(amountIn, amountOutMin, routes, to, deadline);

    require(amountsOut[path.length - 1] >= amountOutMin, "too much slippage");
  }

  function swapTokensForExactTokens(
    uint256,
    uint256,
    address[] calldata,
    address,
    uint256
  ) external pure override returns (uint256[] memory) {
    revert("STFET not supported");
  }

  function getAmountsOut(
    uint256 amountIn,
    address[] calldata path
  ) external view override returns (uint256[] memory amountsOut) {
    require(path.length <= HOPS_LIMIT, "too many hops");

    (uint256 amountOut, ) = _getAmountOut(path[0], path[1], amountIn);
    if (path.length == HOPS_LIMIT) {
      (amountOut, ) = _getAmountOut(path[1], path[2], amountOut);
    }
    amountsOut = new uint256[](path.length);
    amountsOut[path.length - 1] = amountOut;
  }

  function getAmountsIn(uint256, address[] calldata path) external pure returns (uint256[] memory amountsIn) {
    // Not supported
    amountsIn = new uint256[](path.length);
  }

  function _getAmountOut(
    address tokenIn,
    address tokenOut,
    uint256 amountIn
  ) internal view returns (uint256 amountOut, bool stable) {
    address stablePair = velodromeV2Router.poolFor(tokenIn, tokenOut, true, address(velodromeV2Factory));
    address volatilePair = velodromeV2Router.poolFor(tokenIn, tokenOut, false, address(velodromeV2Factory));
    if (velodromeV2Factory.isPool(stablePair)) {
      amountOut = IVelodromeV2Pair(stablePair).getAmountOut(amountIn, tokenIn);
      stable = true;
    } else if (velodromeV2Factory.isPool(volatilePair)) {
      uint256 amountOutVolatile = IVelodromeV2Pair(volatilePair).getAmountOut(amountIn, tokenIn);
      if (amountOutVolatile > amountOut) {
        amountOut = amountOutVolatile;
        stable = false;
      }
    }
  }
}
