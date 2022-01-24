// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

interface IUniswapV3NonfungiblePositionGuard {
  function onReceive(address _poolLogic) external view returns (bool);
}
