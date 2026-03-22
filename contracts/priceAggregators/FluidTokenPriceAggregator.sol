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

import {IAggregatorV3Interface} from "../interfaces/IAggregatorV3Interface.sol";
import {IAssetHandler} from "../interfaces/IAssetHandler.sol";
import {IFToken} from "../interfaces/fluid/IFToken.sol";
import {DynamicUnderlyingAssetPrice} from "./DynamicUnderlyingAssetPrice.sol";

contract FluidTokenPriceAggregator is IAggregatorV3Interface, DynamicUnderlyingAssetPrice {
  IFToken public immutable fluidToken;

  constructor(
    IFToken _fluidToken,
    IAssetHandler _assetHandler
  ) DynamicUnderlyingAssetPrice(_fluidToken.asset(), _assetHandler) {
    fluidToken = _fluidToken;
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
    (
      int256 underlyingPrice,
      uint256 underlyingUpdatedAt,
      uint8 underlyingAggregatorDecimals
    ) = _getUnderlyingPriceData();
    (, , , , , , , , uint256 tokenExchangePrice) = fluidToken.getData();

    // Multiply underlying price by exchange rate and adjust decimals
    // underlying price has 8 decimals, exchange price has 12 decimals
    // final result should have 8 decimals
    answer = (underlyingPrice * int256(tokenExchangePrice)) / 1e12;
    answer = (answer * 1e8) / int256(10 ** underlyingAggregatorDecimals);

    return (0, answer, 0, underlyingUpdatedAt, 0);
  }
}
