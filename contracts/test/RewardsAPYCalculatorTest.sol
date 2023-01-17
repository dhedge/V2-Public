// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "../distribution/RewardsAPYCalculator.sol";

contract RewardsAPYCalculatorTest {
  function calculateAPY(
    uint256 _totalValue,
    uint256 _rewardAmountPerSecond,
    uint256 _rewardTokenPrice
  ) public pure returns (uint256 apy) {
    apy = RewardsAPYCalculator.calculateAPY(_totalValue, _rewardAmountPerSecond, _rewardTokenPrice);
  }
}
