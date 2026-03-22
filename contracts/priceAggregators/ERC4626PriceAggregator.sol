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

import {IERC4626} from "@openzeppelin/v5/contracts/interfaces/IERC4626.sol";

import {IAggregatorV3Interface} from "../interfaces/IAggregatorV3Interface.sol";
import {IAssetHandler} from "../interfaces/IAssetHandler.sol";
import {DynamicUnderlyingAssetPrice} from "./DynamicUnderlyingAssetPrice.sol";

contract ERC4626PriceAggregator is IAggregatorV3Interface, DynamicUnderlyingAssetPrice {
  uint8 public immutable underlyingAssetDecimals;
  IERC4626 public immutable assetToPrice;
  uint8 public immutable assetToPriceDecimals;

  constructor(
    address _erc4626CompatibleAsset,
    IAssetHandler _assetHandler
  ) DynamicUnderlyingAssetPrice(_getUnderlyingAsset(_erc4626CompatibleAsset), _assetHandler) {
    underlyingAssetDecimals = IERC4626(underlyingAsset).decimals();

    assetToPrice = IERC4626(_erc4626CompatibleAsset);
    assetToPriceDecimals = IERC4626(_erc4626CompatibleAsset).decimals();
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

    // The exchange rate is the amount of underlying asset units per 1 token of the ERC4626 asset
    uint256 exchangeRate = assetToPrice.convertToAssets(10 ** assetToPriceDecimals);

    // Multiply underlying price by exchange rate and adjust decimals
    answer = (underlyingPrice * int256(exchangeRate)) / int256(10 ** underlyingAssetDecimals);
    answer = (answer * 1e8) / int256(10 ** underlyingAggregatorDecimals);

    return (0, answer, 0, underlyingUpdatedAt, 0);
  }

  function _getUnderlyingAsset(address _erc4626CompatibleAsset) internal view returns (address asset) {
    asset = IERC4626(_erc4626CompatibleAsset).asset();
  }
}
