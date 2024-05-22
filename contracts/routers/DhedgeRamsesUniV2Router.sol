// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/ramses/IRamsesRouter.sol";
import "../interfaces/uniswapV2/IUniswapV2RouterSwapOnly.sol";

contract DhedgeRamsesUniV2Router is IUniswapV2RouterSwapOnly {
  using SafeERC20 for IERC20;
  using SafeMath for uint256;

  IRamsesRouter public router;

  constructor(IRamsesRouter _router) {
    router = _router;
  }

  function swapExactTokensForTokens(
    uint256 amountIn,
    uint256 amountOutMin,
    address[] calldata path,
    address to,
    uint256 deadline
  ) external override returns (uint256[] memory amountsOut) {
    require(path.length < 4, "too many hops");

    (uint256 out, bool stable) = router.getAmountOut(amountIn, path[0], path[1]);
    IRamsesRouter.route[] memory routes = new IRamsesRouter.route[](path.length == 3 ? 2 : 1);
    routes[0] = IRamsesRouter.route({from: path[0], to: path[1], stable: stable});
    if (path.length == 3) {
      (, stable) = router.getAmountOut(out, path[1], path[2]);
      routes[1] = IRamsesRouter.route({from: path[1], to: path[2], stable: stable});
    }

    IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);

    IERC20(path[0]).approve(address(router), amountIn);
    amountsOut = router.swapExactTokensForTokens(amountIn, amountOutMin, routes, to, deadline);

    require(amountsOut[path.length - 1] >= amountOutMin, "too much slippage");
  }

  function swapTokensForExactTokens(
    uint256,
    uint256,
    address[] calldata,
    address,
    uint256
  ) external pure override returns (uint256[] memory) {
    revert("STFET not supported.");
  }

  function getAmountsOut(
    uint256 amountIn,
    address[] calldata path
  ) external view override returns (uint256[] memory amountsOut) {
    require(path.length < 4, "too many hops");

    (uint256 amountOut, ) = router.getAmountOut(amountIn, path[0], path[1]);
    if (path.length == 3) {
      (amountOut, ) = router.getAmountOut(amountOut, path[1], path[2]);
    }
    amountsOut = new uint256[](path.length);
    amountsOut[path.length - 1] = amountOut;
  }

  /// @dev Not supported
  function getAmountsIn(uint256, address[] calldata path) external pure returns (uint256[] memory amountsIn) {
    amountsIn = new uint256[](path.length);
  }
}
