// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;

interface ISlippageAccumulator {
  function updateSlippageImpactByValue(
    address poolManagerLogic,
    address router,
    uint256 totalValueBefore,
    uint256 totalValueAfter
  ) external;

  function getCumulativeSlippageImpact(address poolManagerLogic) external view returns (uint128 cumulativeSlippage);

  function maxCumulativeSlippage() external view returns (uint128);

  function decayTime() external view returns (uint64);

  function poolFactory() external view returns (address);
}
