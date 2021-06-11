// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface ISynth {
  function proxy() external view returns (address);

  // Mutative functions
  function transferAndSettle(address to, uint256 value) external returns (bool);

  function transferFromAndSettle(
    address from,
    address to,
    uint256 value
  ) external returns (bool);
}
