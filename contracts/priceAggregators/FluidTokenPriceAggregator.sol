// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {SignedSafeMath} from "@openzeppelin/contracts/math/SignedSafeMath.sol";

import {IPoolFactory} from "../interfaces/IPoolFactory.sol";
import {IAssetHandler} from "../interfaces/IAssetHandler.sol";
import {IAggregatorV3Interface} from "../interfaces/IAggregatorV3Interface.sol";
import {IFToken} from "../interfaces/fluid/IFToken.sol";

contract FluidTokenPriceAggregator is IAggregatorV3Interface {
  using SignedSafeMath for int256;

  IFToken public immutable fluidToken;
  IAggregatorV3Interface public immutable underlyingAggregator;
  uint8 public immutable underlyingAggregatorDecimals;

  constructor(IFToken _fluidToken, IPoolFactory _poolFactory) {
    require(address(_fluidToken) != address(0) && address(_poolFactory) != address(0), "invalid address");

    address _underlyingAggregator = IAssetHandler(_poolFactory.getAssetHandler()).priceAggregators(_fluidToken.asset());

    require(_underlyingAggregator != address(0), "invalid aggregator");

    uint8 _underlyingAggregatorDecimals = IAggregatorV3Interface(_underlyingAggregator).decimals();

    require(_underlyingAggregatorDecimals > 0, "invalid decimals");

    fluidToken = _fluidToken;
    underlyingAggregator = IAggregatorV3Interface(_underlyingAggregator);
    underlyingAggregatorDecimals = _underlyingAggregatorDecimals;
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
    (, , , , , , , , uint256 tokenExchangePrice) = fluidToken.getData();

    // Multiply underlying price by exchange rate and adjust decimals
    // underlying price has 8 decimals, exchange price has 12 decimals
    // final result should have 8 decimals
    answer = (underlyingPrice.mul(int256(tokenExchangePrice))).div(1e12);
    answer = answer.mul(1e8).div(int256(10 ** underlyingAggregatorDecimals));

    return (0, answer, 0, underlyingUpdatedAt, 0);
  }
}
