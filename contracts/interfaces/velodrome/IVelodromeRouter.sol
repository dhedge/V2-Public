// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

interface IVelodromeRouter {
  // solhint-disable-next-line contract-name-camelcase
  struct route {
    address from;
    address to;
    bool stable;
  }

  function factory() external pure returns (address);

  function weth() external view returns (address);

  function getAmountsOut(uint256 amountIn, route[] memory routes) external view returns (uint256[] memory amounts);

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

  function addLiquidity(
    address tokenA,
    address tokenB,
    bool stable,
    uint256 amountADesired,
    uint256 amountBDesired,
    uint256 amountAMin,
    uint256 amountBMin,
    address to,
    uint256 deadline
  )
    external
    returns (
      uint256 amountA,
      uint256 amountB,
      uint256 liquidity
    );

  function removeLiquidity(
    address tokenA,
    address tokenB,
    bool stable,
    uint256 liquidity,
    uint256 amountAMin,
    uint256 amountBMin,
    address to,
    uint256 deadline
  ) external returns (uint256 amountA, uint256 amountB);
}
