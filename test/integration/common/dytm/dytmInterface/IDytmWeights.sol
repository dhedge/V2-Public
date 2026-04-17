// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

interface IDytmWeights {
  function setWeight(uint256 collateralTokenId, uint248 debtKey, uint64 weight) external;
}
