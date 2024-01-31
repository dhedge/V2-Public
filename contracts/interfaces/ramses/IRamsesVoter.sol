// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

interface IRamsesVoter {
  function gauges(address pool) external view returns (address gauge);

  function xRam() external view returns (address);
}
