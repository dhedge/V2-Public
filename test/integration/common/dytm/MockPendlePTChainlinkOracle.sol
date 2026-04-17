// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import {IAggregatorV3Interface} from "contracts/interfaces/IAggregatorV3Interface.sol";

/// @dev Simple mock oracle returning a fixed PT/SY rate for testing.
/// The rate should be at or slightly below the actual market conversion rate
/// so the withdrawal slippage check passes (actual value >= expected value).
contract MockPendlePTChainlinkOracle is IAggregatorV3Interface {
  int256 public immutable ptRate;

  constructor(int256 _ptRate) {
    ptRate = _ptRate;
  }

  function decimals() external pure override returns (uint8) {
    return 18;
  }

  function latestRoundData()
    external
    view
    override
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
  {
    return (0, ptRate, 0, block.timestamp, 0);
  }
}
