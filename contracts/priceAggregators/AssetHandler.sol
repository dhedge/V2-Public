// For dHEDGE Asset Price Feeds
// Asset types:
// 0 = Chainlink direct USD price feed with 8 decimals
// 1 = Synthetix synth with Chainlink direct USD price feed
// 2 = Sushi LP tokens
// 3 = Aave V2 Lending Pool Asset
// 4 = Lending Enable Asset
// 5 = Quick LP tokens
// 6 = Balancer LP
// 7 = Uniswap V3 NFT Position Asset
// 8 = Aave V3 Lending Pool Asset
// 9 = Arrakis Liquidity Gauge V4 Asset
// 10 = Balancer V2 Gauge Asset
// 14 = Synthetix + LendingEnabled
// 15 = Velodrome LP/Gauge Asset
// 16 = Stargate LP/Staking Asset
// 17 = Mai Vault Asset
// 20 = Ramses LP/Gauge Asset
// 21 = Flat Money's UNIT
// 22 = Flat Money's Collateral
// 25 = Velodrome V2 LP/Gauge Asset
// 26 = Velodrome CL Position Asset
// 27 = Flat Money's Leverage Asset
// 28 = Compound V3 Comet Asset
// 29 = Ramses CL Position Asset
// 30 = EasySwapperV2 Unrolled Assets
// 31 = Pancake CL NFT Position Asset
// 32 = Flat Money V2 Options Market Asset
// 33 = Flat Money Collateral Lending Enabled
// 34 = Fluid Token
// 35 = Flat Money V2 UNIT
// 36 = Flat Money V2 Perp Market Asset
// 37 = Pendle Principal Token
// 38 = Virtual Token
// 39 = Hyperliquid Perps Account
// 40 = Hyperliquid Spot Token
// 41 = Ondo GM Token Asset
// 42 = Midas mToken Asset
// 43 = Midas Pending Redemption Asset
// 100 = Lyra OptionMarketWrapper Asset
// 101 = Synthetix Futures Perps v1
// 102 = Synthetix Futures Perps v2
// 103 = Synthetix V3 Position Asset
// 104 = Synthetix V3 Perps Position Asset
// 105 = GMX Perps Market Asset
// 106 = Dytm Office Asset
// 200 = Reward Asset (which is linked to other asset types)
// 999 = Deprecated Asset

// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {SafeMathUpgradeable} from "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

import {IAggregatorV3Interface} from "../interfaces/IAggregatorV3Interface.sol";
import {IAssetHandler} from "../interfaces/IAssetHandler.sol";
import {IOracleHeartbeat} from "../interfaces/IOracleHeartbeat.sol";

/// @title dHEDGE Asset Price Feeds
/// @dev Returns USD price with 18 decimals
contract AssetHandler is OwnableUpgradeable, IAssetHandler {
  using SafeMathUpgradeable for uint256;

  uint256 public chainlinkTimeout; // Chainlink oracle timeout period

  // Asset Mappings
  mapping(address => uint16) public override assetTypes; // for asset types refer to header comment
  mapping(address => address) public override priceAggregators;

  // Per-asset maximum price age floor (seconds). 0 = no freshness check required.
  mapping(address => uint256) public override assetMaxPriceAge;

  event SetChainlinkTimeout(uint256 timeout);

  event AssetMaxPriceAgeSet(address indexed asset, uint256 maxAge);

  /// @notice initialisation for the contract
  /// @param assets An array of assets to initialise
  function initialize(Asset[] memory assets) external initializer {
    __Ownable_init();

    setChainlinkTimeout(90000); // 25 hours
    addAssets(assets);
  }

  /* ========== VIEWS ========== */

  /// @dev Calculate the USD price of a given asset.
  /// @param asset the asset address
  /// @return price Returns the latest price of a given asset (decimal: 18)
  function getUSDPrice(address asset) external view override returns (uint256 price) {
    (price, ) = _getUSDPrice(asset);
  }

  /// @dev Calculate the USD price of a given asset with timestamp and max price age.
  /// @param asset the asset address
  /// @return price Returns the latest price of a given asset (decimal: 18)
  /// @return updatedAt Returns the timestamp of the price update
  /// @return maxPriceAge Returns the configured maximum price age for the asset (0 if not set)
  function getUSDPriceWithTime(
    address asset
  ) external view override returns (uint256 price, uint256 updatedAt, uint256 maxPriceAge) {
    (price, updatedAt) = _getUSDPrice(asset);
    maxPriceAge = assetMaxPriceAge[asset];
  }

  /// @dev Internal function to get USD price with timestamp
  /// @param asset the asset address
  /// @return price Returns the latest price of a given asset (decimal: 18)
  /// @return updatedAt Returns the timestamp of the price update
  function _getUSDPrice(address asset) internal view returns (uint256 price, uint256 updatedAt) {
    address aggregator = priceAggregators[asset];

    require(aggregator != address(0), "Price aggregator not found");

    try IAggregatorV3Interface(aggregator).latestRoundData() returns (
      uint80,
      int256 _price,
      uint256,
      uint256 _updatedAt,
      uint80
    ) {
      // Aggregators can override the default chainlinkTimeout by exposing oracleHeartbeat().
      // Used by feeds with slower update cadences (e.g. Ondo's ~2 day attestation oracle).
      if (_updatedAt.add(chainlinkTimeout) < block.timestamp) {
        uint256 timeout = chainlinkTimeout;
        try IOracleHeartbeat(aggregator).oracleHeartbeat() returns (uint256 heartbeat) {
          timeout = heartbeat;
          // solhint-disable-next-line no-empty-blocks
        } catch {}
        require(_updatedAt.add(timeout) >= block.timestamp, "Chainlink price expired");
      }

      if (_price > 0) {
        price = uint256(_price).mul(10 ** 10); // convert Chainlink decimals 8 -> 18
      }
      updatedAt = _updatedAt;
    } catch {
      revert("Price get failed");
    }

    require(price > 0, "Price not available");
  }

  /* ========== MUTATIVE FUNCTIONS ========== */

  /* ---------- From Owner ---------- */

  /// @notice Setting the timeout for the Chainlink price feed
  /// @param newTimeoutPeriod A new time in seconds for the timeout
  function setChainlinkTimeout(uint256 newTimeoutPeriod) public onlyOwner {
    chainlinkTimeout = newTimeoutPeriod;
    emit SetChainlinkTimeout(newTimeoutPeriod);
  }

  /// @notice Add valid asset with price aggregator
  /// @param asset Address of the asset to add
  /// @param assetType Type of the asset
  /// @param aggregator Address of the aggregator
  function addAsset(address asset, uint16 assetType, address aggregator) public override onlyOwner {
    require(asset != address(0), "asset address cannot be 0");
    require(aggregator != address(0), "aggregator address cannot be 0");

    assetTypes[asset] = assetType;
    priceAggregators[asset] = aggregator;

    emit AddedAsset(asset, assetType, aggregator);
  }

  /// @notice Add valid assets with price aggregator
  /// @param assets An array of assets to add
  function addAssets(Asset[] memory assets) public override onlyOwner {
    for (uint8 i = 0; i < assets.length; i++) {
      addAsset(assets[i].asset, assets[i].assetType, assets[i].aggregator);
    }
  }

  /// @notice Remove valid asset
  /// @param asset Address of the asset to remove
  function removeAsset(address asset) external override onlyOwner {
    assetTypes[asset] = 0;
    priceAggregators[asset] = address(0);
    assetMaxPriceAge[asset] = 0;

    emit RemovedAsset(asset);
  }

  /// @notice Set the maximum price age floor for an asset
  /// @dev A non-zero value enables the freshness check for this asset on deposits.
  ///      Set to 0 to disable the freshness check.
  /// @param asset Address of the asset
  /// @param maxAge Maximum allowed price age in seconds (0 to disable)
  function setAssetMaxPriceAge(address asset, uint256 maxAge) external override onlyOwner {
    require(priceAggregators[asset] != address(0), "Asset not found");
    assetMaxPriceAge[asset] = maxAge;
    emit AssetMaxPriceAgeSet(asset, maxAge);
  }

  uint256[49] private __gap;
}
