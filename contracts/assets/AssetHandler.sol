// For dHEDGE Asset Price Feeds
// Asset types:
// 0 = Chainlink direct USD price feed with 8 decimals
// 1 = Synthetix synth with Chainlink direct USD price feed
// 2 = Sushi LP tokens
// 3 = Aave Lending Pool Asset
// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

import "../interfaces/IAggregatorV3Interface.sol";
import "../interfaces/IAssetHandler.sol";

/**
 * @title dHEDGE Asset Price Feeds
 * @dev Returns Chainlink USD price feed with 18 decimals
 * Asset types:
 * 0 = Chainlink direct USD price feed with 8 decimals
 */
contract AssetHandler is OwnableUpgradeable, IAssetHandler {
  using SafeMathUpgradeable for uint256;

  uint256 public chainlinkTimeout; // Chainlink oracle timeout period

  // Asset Mappings
  mapping(address => uint16) public override assetTypes; // for asset types refer to header comment
  mapping(address => address) public override priceAggregators;

  event SetChainlinkTimeout(uint256 _chainlinkTimeout);

  /// @dev initialisation for the contract
  /// @param assets An array of assets to initialise
  function initialize(Asset[] memory assets) external initializer {
    __Ownable_init();

    chainlinkTimeout = 90000; // 25 hours
    addAssets(assets);
  }

  /* ========== VIEWS ========== */

  /**
   * @notice Currenly only use chainlink price feed.
   * @dev Calculate the USD price of a given asset.
   * @param asset the asset address
   * @return price Returns the latest price of a given asset (decimal: 18)
   */
  function getUSDPrice(address asset) external view override returns (uint256 price) {
    address aggregator = priceAggregators[asset];

    require(aggregator != address(0), "Price aggregator not found");

    try IAggregatorV3Interface(aggregator).latestRoundData() returns (
      uint80,
      int256 _price,
      uint256,
      uint256 updatedAt,
      uint80
    ) {
      // check chainlink price updated within 25 hours
      require(updatedAt.add(chainlinkTimeout) >= block.timestamp, "Chainlink price expired");

      if (_price > 0) {
        price = uint256(_price).mul(10**10); // convert Chainlink decimals 8 -> 18
      }
    } catch {
      revert("Price get failed");
    }

    require(price > 0, "Price not available");
  }

  /* ========== MUTATIVE FUNCTIONS ========== */

  /* ---------- From Owner ---------- */

  /// @dev Setting the timeout for the Chainlink price feed
  /// @param newTimeoutPeriod A new time in seconds for the timeout
  function setChainlinkTimeout(uint256 newTimeoutPeriod) external onlyOwner {
    chainlinkTimeout = newTimeoutPeriod;
    emit SetChainlinkTimeout(newTimeoutPeriod);
  }

  /// @dev Add valid asset with price aggregator
  /// @param asset Address of the asset to add
  /// @param assetType Type of the asset
  /// @param aggregator Address of the aggregator
  function addAsset(
    address asset,
    uint16 assetType,
    address aggregator
  ) public override onlyOwner {
    require(asset != address(0), "asset address cannot be 0");
    require(aggregator != address(0), "aggregator address cannot be 0");

    assetTypes[asset] = assetType;
    priceAggregators[asset] = aggregator;

    emit AddedAsset(asset, assetType, aggregator);
  }

  /// @dev Add valid assets with price aggregator
  /// @param assets An array of assets to add
  function addAssets(Asset[] memory assets) public override onlyOwner {
    for (uint8 i = 0; i < assets.length; i++) {
      addAsset(assets[i].asset, assets[i].assetType, assets[i].aggregator);
    }
  }

  /// @dev Remove valid asset
  /// @param asset Address of the asset to remove
  function removeAsset(address asset) external override onlyOwner {
    assetTypes[asset] = 0;
    priceAggregators[asset] = address(0);

    emit RemovedAsset(asset);
  }

  uint256[50] private __gap;
}
