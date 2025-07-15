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

import {IERC4626} from "@openzeppelin/v5/contracts/interfaces/IERC4626.sol";

import {IPoolFactory} from "../interfaces/IPoolFactory.sol";
import {IAssetHandler} from "../interfaces/IAssetHandler.sol";
import {IAggregatorV3Interface} from "../interfaces/IAggregatorV3Interface.sol";

contract ERC4626PriceAggregator is IAggregatorV3Interface {
  IERC4626 public immutable assetToPrice;
  uint8 public immutable assetToPriceDecimals;
  uint8 public immutable underlyingAssetDecimals;

  IAggregatorV3Interface public immutable underlyingAggregator;
  uint8 public immutable underlyingAggregatorDecimals;

  constructor(address _erc4626CompatibleAsset, IPoolFactory _poolFactory) {
    require(_erc4626CompatibleAsset != address(0) && address(_poolFactory) != address(0), "invalid address");

    address underlyingAsset = IERC4626(_erc4626CompatibleAsset).asset();
    address _underlyingAggregator = IAssetHandler(_poolFactory.getAssetHandler()).priceAggregators(underlyingAsset);

    require(_underlyingAggregator != address(0), "invalid aggregator");

    assetToPrice = IERC4626(_erc4626CompatibleAsset);
    assetToPriceDecimals = IERC4626(_erc4626CompatibleAsset).decimals();
    underlyingAssetDecimals = IERC4626(underlyingAsset).decimals();
    underlyingAggregator = IAggregatorV3Interface(_underlyingAggregator);
    underlyingAggregatorDecimals = IAggregatorV3Interface(_underlyingAggregator).decimals();
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
    (, int256 underlyingPrice, , uint256 underlyingUpdatedAt, ) = underlyingAggregator.latestRoundData();

    // The exchange rate is the amount of underlying asset units per 1 token of the ERC4626 asset
    uint256 exchangeRate = assetToPrice.convertToAssets(10 ** assetToPriceDecimals);

    // Multiply underlying price by exchange rate and adjust decimals
    answer = (underlyingPrice * int256(exchangeRate)) / int256(10 ** underlyingAssetDecimals);
    answer = (answer * 1e8) / int256(10 ** underlyingAggregatorDecimals);

    return (0, answer, 0, underlyingUpdatedAt, 0);
  }
}
