// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

interface IGmxPrice {
  struct Price {
    uint256 min;
    uint256 max;
  }
}
