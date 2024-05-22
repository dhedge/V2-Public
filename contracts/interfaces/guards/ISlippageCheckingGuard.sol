// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

interface ISlippageCheckingGuard {
  function isSlippageCheckingGuard() external view returns (bool);
}
