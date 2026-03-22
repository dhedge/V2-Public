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
// Copyright (c) dHEDGE DAO
//
// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {Math} from "@openzeppelin/v5/contracts/utils/math/Math.sol";

import {IAggregatorV3Interface} from "../interfaces/IAggregatorV3Interface.sol";
import {IAssetHandler} from "../interfaces/IAssetHandler.sol";
import {DynamicUnderlyingAssetPrice} from "./DynamicUnderlyingAssetPrice.sol";

contract PendlePTPriceAggregator is IAggregatorV3Interface, DynamicUnderlyingAssetPrice {
  IAggregatorV3Interface public immutable pendleChainlinkOracle;
  uint8 public immutable pendleChainlinkOracleDecimals;

  constructor(
    address _syEquivalentToken,
    IAggregatorV3Interface _pendleChainlinkOracle,
    IAssetHandler _assetHandler
  ) DynamicUnderlyingAssetPrice(_syEquivalentToken, _assetHandler) {
    require(address(_pendleChainlinkOracle) != address(0), "invalid address");

    pendleChainlinkOracle = _pendleChainlinkOracle;
    pendleChainlinkOracleDecimals = _pendleChainlinkOracle.decimals();
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
    (, int256 ptPrice, , uint256 ptPriceUpdateAt, ) = pendleChainlinkOracle.latestRoundData();
    (
      int256 underlyingPrice,
      uint256 underlyingUpdatedAt,
      uint8 underlyingAggregatorDecimals
    ) = _getUnderlyingPriceData();

    // Answer is in underlyingAggregator decimals
    answer = (ptPrice * underlyingPrice) / int256(10 ** pendleChainlinkOracleDecimals);
    // Adjust answer to 8 decimals
    answer = (answer * 1e8) / int256(10 ** underlyingAggregatorDecimals);

    return (0, answer, 0, Math.min(underlyingUpdatedAt, ptPriceUpdateAt), 0);
  }
}
