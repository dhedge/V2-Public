// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {IAggregatorV3Interface} from "../interfaces/IAggregatorV3Interface.sol";

import {PrecompileHelper} from "../utils/hyperliquid/PrecompileHelper.sol";

/// @title HyperliquidSpotPriceAggregator
/// @notice Used for spot tokens on HyperCore and their corresponding linked contract on HyperEVM.
///         Must be deployed for each spot token on HyperCore and the linked contract on HyperEVM
///         should use this contract as the price aggregator.
/// @dev Use this with caution given that for thin liquidity markets, the spot price can be manipulated.
///      One can consider using Chainlink oracles for such markets (if available).
/// @dev WARNING: MUST NOT BE USED FOR USDC. Use Chainlink USDC/USD price feed instead.
/// @dev This should have `latestRoundData` function as chainlink pricing oracle.
contract HyperliquidSpotPriceAggregator is IAggregatorV3Interface, PrecompileHelper {
  /////////////////////////////////////////////
  //                 State                   //
  /////////////////////////////////////////////

  /// @notice The spot index of the token on HyperCore.
  uint64 public immutable SPOT_INDEX;

  /// @notice Chainlink USDC/USD price feed for converting USDC-denominated prices to USD.
  IAggregatorV3Interface public immutable USDC_USD_FEED;

  /////////////////////////////////////////////
  //               Functions                 //
  /////////////////////////////////////////////

  constructor(uint64 _spotIndex, address _usdcUsdFeed) {
    require(_spotIndex != 0, "Spot index 0");
    require(_usdcUsdFeed != address(0), "Invalid USDC/USD feed");

    SPOT_INDEX = _spotIndex;
    USDC_USD_FEED = IAggregatorV3Interface(_usdcUsdFeed);
  }

  function decimals() external pure override returns (uint8) {
    return 8;
  }

  /// @notice Returns the latest price in USD by converting the USDC-denominated spot price.
  /// @dev Multiplies the spot price (TOKEN/USDC) by USDC/USD rate to get TOKEN/USD.
  ///      Both prices use 8 decimals, so we divide by 10^8 to maintain 8 decimal precision.
  function latestRoundData()
    external
    view
    override
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
  {
    // Get spot price in USDC (8 decimals)
    uint256 spotPriceInUSDC = normalizedSpotPx(SPOT_INDEX);

    // Get USDC/USD rate from Chainlink (8 decimals)
    (, int256 usdcUsdRate, , , ) = USDC_USD_FEED.latestRoundData();
    require(usdcUsdRate > 0, "Invalid USDC/USD price");

    // Convert to USD: (TOKEN/USDC) * (USDC/USD) = TOKEN/USD
    // spotPriceInUSDC is 8 decimals, usdcUsdRate is 8 decimals
    uint256 spotPriceInUSD = (spotPriceInUSDC * uint256(usdcUsdRate)) / 1e8;

    return (0, int256(spotPriceInUSD), 0, block.timestamp, 0);
  }
}
