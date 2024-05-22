// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

import "../interfaces/IAggregatorV3Interface.sol";
import "../interfaces/IERC20Extended.sol"; // includes decimals()

/**
 * @title Fixed price aggregator. Takes the price at construction
 * @notice You can use this contract for any price.
 * @dev This should have `latestRoundData` function as chainlink pricing oracle.
 */
contract FixedPriceAggregator is IAggregatorV3Interface {
  int256 public price;

  constructor(int256 _price) {
    price = _price;
  }

  /**
   * @notice Get the latest round data. Should be the same format as chainlink aggregator.
   * @return roundId The round ID.
   * @return answer The price - the latest round data of USD (price decimal: 8)
   * @return startedAt Timestamp of when the round started.
   * @return updatedAt Timestamp of when the round was updated.
   * @return answeredInRound The round ID of the round in which the answer was computed.
   */
  function latestRoundData()
    external
    view
    override
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
  {
    return (0, price, 0, block.timestamp, 0);
  }

  function decimals() external pure override returns (uint8) {
    return 8;
  }
}
