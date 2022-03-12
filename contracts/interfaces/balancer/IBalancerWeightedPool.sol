// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import "./IBalancerPool.sol";

interface IBalancerWeightedPool is IBalancerPool {
  function getNormalizedWeights() external view returns (uint256[] memory);
}
