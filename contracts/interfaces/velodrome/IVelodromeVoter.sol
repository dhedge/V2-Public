// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

interface IVelodromeVoter {
  function gauges(address pool) external view returns (address gauge);

  function isAlive(address gauge) external view returns (bool);
}
