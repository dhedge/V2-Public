// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

interface IVelodromeFactory {
  function getPair(
    address tokenA,
    address tokenB,
    bool stable
  ) external view returns (address pair);
}
