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

pragma solidity 0.7.6;

import {Math} from "@openzeppelin/contracts/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/SafeCast.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {SignedSafeMath} from "@openzeppelin/contracts/math/SignedSafeMath.sol";

import {IAggregatorV3Interface} from "../interfaces/IAggregatorV3Interface.sol";
import {DhedgeMath} from "../utils/DhedgeMath.sol";

contract ChainlinkTWAPAggregator is IAggregatorV3Interface {
  enum ResultingPrice {
    MAX,
    MIN,
    CHAINLINK,
    TWAP
  }

  using Math for uint256;
  using SafeCast for *;
  using SafeMath for uint256;
  using SignedSafeMath for int256;
  using DhedgeMath for *;

  IAggregatorV3Interface public immutable chainlinkAggregator;
  IAggregatorV3Interface public immutable twapAggregator;
  /// @dev max difference percent between chainlink and twap. 1e18 is 100%
  uint256 public immutable maxPriceDifferencePercent;
  ResultingPrice public immutable resultingPriceType;

  function(uint256, uint256) internal pure returns (uint256) private immutable _getResultingPrice;

  constructor(
    IAggregatorV3Interface _chainlinkAggregator,
    IAggregatorV3Interface _twapAggregator,
    uint256 _maxPriceDifferencePercent,
    ResultingPrice _resultingPriceType
  ) {
    require(address(_chainlinkAggregator) != address(0) && address(_twapAggregator) != address(0), "invalid address");

    require(_chainlinkAggregator.decimals() == 8 && _twapAggregator.decimals() == 8, "invalid decimals");

    require(_maxPriceDifferencePercent > 0 && _maxPriceDifferencePercent <= 1e18, "invalid percent");

    chainlinkAggregator = _chainlinkAggregator;
    twapAggregator = _twapAggregator;
    maxPriceDifferencePercent = _maxPriceDifferencePercent;
    resultingPriceType = _resultingPriceType;
    _getResultingPrice = _getResultingPriceFunc(_resultingPriceType);
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
    (, int256 chainlinkPriceD8, , uint256 chainlinkUpdatedAt, ) = chainlinkAggregator.latestRoundData();

    try twapAggregator.latestRoundData() returns (uint80, int256 twapD8, uint256, uint256 twapUpdatedAt, uint80) {
      uint256 priceDifference = chainlinkPriceD8.sub(twapD8).abs();
      uint256 minPrice = chainlinkPriceD8.toUint256().min(twapD8.toUint256());
      uint256 differencePercent = priceDifference.mul(1e18).div(minPrice);

      require(differencePercent <= maxPriceDifferencePercent, "price mismatch");

      answer = _getResultingPrice(chainlinkPriceD8.toUint256(), twapD8.toUint256()).toInt256();
      updatedAt = answer == chainlinkPriceD8 ? chainlinkUpdatedAt : twapUpdatedAt;
    } catch {
      // If TWAP aggregator fails, return Chainlink price
      answer = chainlinkPriceD8;
      updatedAt = chainlinkUpdatedAt;
    }

    return (0, answer, 0, updatedAt, 0);
  }

  /// @dev Use only at initialization (during constructor)
  function _getResultingPriceFunc(
    ResultingPrice _type
  ) internal pure returns (function(uint256, uint256) internal pure returns (uint256)) {
    if (_type == ResultingPrice.MAX) {
      return Math.max;
    } else if (_type == ResultingPrice.MIN) {
      return Math.min;
    } else if (_type == ResultingPrice.CHAINLINK) {
      return _first;
    } else if (_type == ResultingPrice.TWAP) {
      return _second;
    } else {
      revert("unknown type");
    }
  }

  function _first(uint256 a, uint256) internal pure returns (uint256) {
    return a;
  }

  function _second(uint256, uint256 b) internal pure returns (uint256) {
    return b;
  }
}
