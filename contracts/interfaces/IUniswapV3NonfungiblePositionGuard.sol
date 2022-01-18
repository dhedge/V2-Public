// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

interface IUniswapV3NonfungiblePositionGuard {
  function uniV3PositionsLimit() external view returns (uint256);
}
