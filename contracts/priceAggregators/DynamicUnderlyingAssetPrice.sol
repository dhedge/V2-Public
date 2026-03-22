// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {IAggregatorV3Interface} from "../interfaces/IAggregatorV3Interface.sol";
import {IAssetHandler} from "../interfaces/IAssetHandler.sol";

/// @title DynamicUnderlyingAssetPrice
/// @notice Base contract for price aggregators that derive price from an underlying asset's aggregator.
///         Always reads the current aggregator from AssetHandler dynamically — no stored references,
///         no need for manual updates or keeper infrastructure.
abstract contract DynamicUnderlyingAssetPrice {
  IAssetHandler public immutable assetHandler;
  address public immutable underlyingAsset;

  constructor(address _underlyingAsset, IAssetHandler _assetHandler) {
    require(address(_assetHandler) != address(0) && _underlyingAsset != address(0), "invalid address");

    underlyingAsset = _underlyingAsset;
    assetHandler = _assetHandler;
  }

  /// @notice Returns the current underlying asset price data from the dynamically resolved aggregator.
  /// @return price The underlying asset price
  /// @return updatedAt Timestamp of the last price update
  /// @return aggregatorDecimals Decimals of the underlying aggregator
  function _getUnderlyingPriceData() internal view returns (int256 price, uint256 updatedAt, uint8 aggregatorDecimals) {
    address aggregator = assetHandler.priceAggregators(underlyingAsset);
    require(aggregator != address(0), "invalid aggregator");

    (, price, , updatedAt, ) = IAggregatorV3Interface(aggregator).latestRoundData();
    aggregatorDecimals = IAggregatorV3Interface(aggregator).decimals();
  }
}
