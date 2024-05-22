// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";

import {IViewer} from "../interfaces/flatMoney/IViewer.sol";
import {IAggregatorV3Interface} from "../interfaces/IAggregatorV3Interface.sol";

contract FlatMoneyUNITPriceAggregator is IAggregatorV3Interface {
  using SafeMath for uint256;

  IViewer public viewer;

  constructor(IViewer _viewer) {
    require(address(_viewer) != address(0), "invalid address");

    viewer = _viewer;
  }

  function decimals() external pure override returns (uint8) {
    return 8;
  }

  function latestRoundData()
    external
    view
    override
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
  {
    uint256 priceD18 = viewer.getFlatcoinPriceInUSD();
    return (0, int256(priceD18.div(10 ** 10)), 0, block.timestamp, 0);
  }
}
