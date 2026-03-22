//
//        __  __    __  ________  _______    ______   ________
//       /  |/  |  /  |/        |/       \  /      \ /        |
//   ____$$ |$$ |  $$ |$$$$$$$$/ $$$$$$$  |/$$$$$$  |$$$$$$$$/
//  /    $$ |$$ |__$$ |$$ |__    $$ |  $$ |$$ | _$$/ $$ |__
// /$$$$$$$ |$$    $$ |$$    |   $$ |  $$ |$$ |/    |$$    |
// $$ |  $$ |$$$$$$$$ |$$$$$/    $$ |  $$ |$$ |$$$$ |$$$$$/
// $$ \__$$ |$$ |  $$ |$$ |_____ $$ |__$$ |$$ \__$$ |$$ |_____
// $$    $$ |$$ |  $$ |$$       |$$    $$/ $$    $$/ $$       |
//  $$$$$$$/ $$/   $$/ $$$$$$$$/ $$$$$$$/   $$$$$$/  $$$$$$$$/
//
// dHEDGE DAO - https://dhedge.org
//
// Copyright (c) 2025 dHEDGE DAO
//
// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {IAggregatorV3Interface} from "../interfaces/IAggregatorV3Interface.sol";

contract ChainlinkAggregatorWrapper is IAggregatorV3Interface {
  // solhint-disable-next-line const-name-snakecase
  uint8 public constant decimals = 8;

  IAggregatorV3Interface public immutable chainlinkAggregator;
  uint8 public immutable chainlinkDecimals;

  constructor(address _chainlinkAggregator) {
    require(_chainlinkAggregator != address(0), "invalid address");

    require(IAggregatorV3Interface(_chainlinkAggregator).decimals() != 8, "wrapper not needed");

    chainlinkAggregator = IAggregatorV3Interface(_chainlinkAggregator);
    chainlinkDecimals = IAggregatorV3Interface(_chainlinkAggregator).decimals();
  }

  function latestRoundData()
    external
    view
    override
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
  {
    (roundId, answer, startedAt, updatedAt, answeredInRound) = chainlinkAggregator.latestRoundData();

    answer = (answer * int256(10 ** decimals)) / int256(10 ** chainlinkDecimals);
  }
}
