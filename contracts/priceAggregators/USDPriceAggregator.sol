// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

import {IAggregatorV3Interface} from "../interfaces/IAggregatorV3Interface.sol";

/// @title USD price aggregator. For dHEDGE assets, where pricing happens in asset guard.
/// @notice You can use this contract for usd price = $1.
/// @dev This should have `latestRoundData` function as chainlink pricing oracle.
contract USDPriceAggregator is IAggregatorV3Interface {
  function decimals() external pure override returns (uint8) {
    return 8;
  }

  function latestRoundData()
    external
    view
    override
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
  {
    return (0, 10 ** 8, 0, block.timestamp, 0);
  }
}
