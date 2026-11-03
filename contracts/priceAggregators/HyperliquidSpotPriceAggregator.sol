// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {IAggregatorV3Interface} from "../interfaces/IAggregatorV3Interface.sol";

import {PrecompileHelper} from "../utils/hyperliquid/PrecompileHelper.sol";

/// @title HyperliquidSpotPriceAggregator
/// @notice Used for spot tokens on HyperCore and their corresponding linked contract on HyperEVM.
///         Must be deployed for each spot token on HyperCore and the linked contract on HyperEVM
///         should use this contract as the price aggregator.
/// @dev The spot price comes from Hyperliquid's own book, which can trade away from the asset's real price (a
///      bridged token losing its peg, a thin book). Every price is therefore checked against the oracle price of a
///      perp on the same asset, and the aggregator reverts instead of returning a price that is too far from it.
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

  /// @notice Perp index (as read by the oracle price precompile) of a perp on the same asset, e.g. BTC for UBTC.
  ///         HIP-3 perps use `assetId - 100000`.
  uint32 public immutable REFERENCE_PERP_INDEX;

  /// @notice Maximum distance of the spot price from the reference perp's oracle price, in basis points.
  uint256 public immutable MAX_DEVIATION_BPS;

  /////////////////////////////////////////////
  //               Functions                 //
  /////////////////////////////////////////////

  constructor(uint64 _spotIndex, address _usdcUsdFeed, uint32 _referencePerpIndex, uint256 _maxDeviationBps) {
    require(_spotIndex != 0, "Spot index 0");
    require(_usdcUsdFeed != address(0), "Invalid USDC/USD feed");
    require(_maxDeviationBps > 0 && _maxDeviationBps < 10_000, "invalid max deviation");

    SPOT_INDEX = _spotIndex;
    USDC_USD_FEED = IAggregatorV3Interface(_usdcUsdFeed);
    REFERENCE_PERP_INDEX = _referencePerpIndex;
    MAX_DEVIATION_BPS = _maxDeviationBps;
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
    uint256 spotPriceInUSDC = normalizedSpotPx(SPOT_INDEX);

    // Both in 8 decimals: perp oracle prices normalize to 6.
    uint256 referencePrice = normalizedOraclePx(REFERENCE_PERP_INDEX) * 1e2;
    uint256 deviation = spotPriceInUSDC > referencePrice
      ? spotPriceInUSDC - referencePrice
      : referencePrice - spotPriceInUSDC;
    require(deviation * 10_000 <= referencePrice * MAX_DEVIATION_BPS, "spot price deviates from oracle");

    (, int256 usdcUsdRate, , uint256 usdcUsdUpdatedAt, ) = USDC_USD_FEED.latestRoundData();
    require(usdcUsdRate > 0, "Invalid USDC/USD price");

    // Convert to USD: (TOKEN/USDC) * (USDC/USD) = TOKEN/USD, both 8 decimals
    uint256 spotPriceInUSD = (spotPriceInUSDC * uint256(usdcUsdRate)) / 1e8;

    // Return the USDC/USD feed timestamp so downstream staleness checks have a real timestamp (the spot precompile has none).
    return (0, int256(spotPriceInUSD), 0, usdcUsdUpdatedAt, 0);
  }
}
