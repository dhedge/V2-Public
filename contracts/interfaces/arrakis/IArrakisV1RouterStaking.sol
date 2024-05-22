// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.7.6;

interface IArrakisV1RouterStaking {
  function addLiquidityAndStake(
    address gauge,
    uint256 amount0Max,
    uint256 amount1Max,
    uint256 amount0Min,
    uint256 amount1Min,
    uint256 amountSharesMin,
    address receiver
  ) external returns (uint256 amount0, uint256 amount1, uint256 mintAmount);

  function removeLiquidityAndUnstake(
    address gauge,
    uint256 burnAmount,
    uint256 amount0Min,
    uint256 amount1Min,
    address receiver
  ) external returns (uint256 amount0, uint256 amount1, uint128 liquidityBurned);
}
