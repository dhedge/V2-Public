// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

interface IUniswapV2Factory {
  function getPair(address tokenA, address tokenB) external view returns (address pair);
}
