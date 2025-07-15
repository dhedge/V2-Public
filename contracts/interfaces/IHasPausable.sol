// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

interface IHasPausable {
  function isPaused() external view returns (bool);

  function pausedPools(address pool) external view returns (bool);

  function tradingPausedPools(address pool) external view returns (bool);
}
