// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

interface IVelodromeV2Pair {
  function token0() external view returns (address);

  function token1() external view returns (address);

  function claimable0(address user) external view returns (uint256);

  function claimable1(address user) external view returns (uint256);

  function totalSupply() external view returns (uint256);

  function quote(
    address tokenIn,
    uint256 amountIn,
    uint256 granularity
  ) external view returns (uint256 amountOut);

  function burn(address to) external returns (uint256 amount0, uint256 amount1);

  function getReserves()
    external
    view
    returns (
      uint112 reserve0,
      uint112 reserve1,
      uint32 blockTimestampLast
    );

  function claimFees() external returns (uint256 claimed0, uint256 claimed1);

  function getAmountOut(uint256 amountIn, address tokenIn) external view returns (uint256);
}
