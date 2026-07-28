// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;
pragma abicoder v2;

interface IAssetHandler {
  event AddedAsset(address asset, uint16 assetType, address aggregator);
  event RemovedAsset(address asset);

  struct Asset {
    address asset;
    uint16 assetType;
    address aggregator;
  }

  function addAsset(address asset, uint16 assetType, address aggregator) external;

  function addAssets(Asset[] memory assets) external;

  function removeAsset(address asset) external;

  function priceAggregators(address asset) external view returns (address aggregator);

  function assetTypes(address asset) external view returns (uint16 assetType);

  function setAssetMaxPriceAge(address asset, uint256 maxAge) external;

  function assetMaxPriceAge(address asset) external view returns (uint256);

  function getUSDPrice(address asset) external view returns (uint256 price);

  function getUSDPriceWithTime(
    address asset
  ) external view returns (uint256 price, uint256 updatedAt, uint256 maxPriceAge);
}
