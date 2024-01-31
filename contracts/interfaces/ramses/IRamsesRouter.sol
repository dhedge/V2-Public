// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

interface IRamsesRouter {
  // solhint-disable-next-line contract-name-camelcase
  struct route {
    address from;
    address to;
    bool stable;
  }

  function pairFor(
    address tokenA,
    address tokenB,
    bool stable
  ) external view returns (address pair);

  function getAmountOut(
    uint256 amountIn,
    address tokenIn,
    address tokenOut
  ) external view returns (uint256 amount, bool stable);

  function swapExactTokensForTokens(
    uint256 amountIn,
    uint256 amountOutMin,
    route[] calldata routes,
    address to,
    uint256 deadline
  ) external returns (uint256[] memory amounts);
}
