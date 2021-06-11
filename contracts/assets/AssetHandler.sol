// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2; // TODO: Can we upgrade the solidity versions to include ABIEncoderV2 by default? (not experimental)

import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol";

import "../interfaces/IAggregatorV3Interface.sol";
import "../interfaces/IAssetHandler.sol";

/**
 * @title dHEDGE Asset Price Feeds
 * @dev Returns Chainlink USD price feed with 18 decimals
 * Asset types: 
 * 0 = Chainlink direct USD price feed with 8 decimals
 */
contract AssetHandler is Initializable, OwnableUpgradeSafe, IAssetHandler {
  using SafeMath for uint256;

  uint256 public chainlinkTimeout; // Chainlink oracle timeout period
  address public poolFactory;

  // Asset Price feeds
  mapping(address => uint8) public override assetTypes; // for asset types refer to header comment
  mapping(address => address) public override priceAggregators;

  // Note: in the future, we can add more mappings for new assets if necessary (eg ERC721)

  function initialize(address _poolFactory, Asset[] memory assets) public initializer {
    require(_poolFactory != address(0), "Invalid poolFactory");
    OwnableUpgradeSafe.__Ownable_init();

    poolFactory = _poolFactory;
    chainlinkTimeout = 90000; // 25 hours
    addAssets(assets);
  }

  /* ========== VIEWS ========== */

  function getAssetTypeAndAggregator(address asset) public view override returns (uint8, address) {
    return (assetTypes[asset], priceAggregators[asset]);
  }

  /**
   * @notice Currenly only use chainlink price feed.
   * @dev Calculate the USD price of a given asset.
   * @param asset the asset address
   * @return price Returns the latest price of a given asset (decimal: 18)
   */
  function getUSDPrice(address asset) public view override returns (uint256 price) {
    address aggregator = priceAggregators[asset];
    uint8 assetType = assetTypes[asset];

    require(aggregator != address(0), "Price aggregator not found");

    if (assetType == 0) {
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
    }

    require(price > 0, "Price not available");
  }

  /* ========== MUTATIVE FUNCTIONS ========== */

  /* ---------- From Owner ---------- */

  function setPoolFactory(address _poolFactory) external onlyOwner {
    require(_poolFactory != address(0), "Invalid poolFactory");
    poolFactory = _poolFactory;
  }

  function setChainlinkTimeout(uint256 newTimeoutPeriod) external onlyOwner {
    chainlinkTimeout = newTimeoutPeriod;
  }

  /// Add valid asset with price aggregator
  function addAsset(
    address asset,
    uint8 assetType,
    address aggregator
  ) public override onlyOwner {
    assetTypes[asset] = assetType;
    priceAggregators[asset] = aggregator;

    emit AddedAsset(asset, assetType, aggregator);
  }

  function addAssets(Asset[] memory assets) public override onlyOwner {
    for (uint8 i = 0; i < assets.length; i++) {
      addAsset(assets[i].asset, assets[i].assetType, assets[i].aggregator);
    }
  }

  /// Remove valid asset
  function removeAsset(address asset) public override onlyOwner {
    assetTypes[asset] = 0;
    priceAggregators[asset] = address(0);

    emit RemovedAsset(asset);
  }

  uint256[50] private __gap;
}
