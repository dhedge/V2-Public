// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

pragma experimental ABIEncoderV2;

interface IAssetHandler {
  event AddedAsset(address asset, uint8 assetType, address aggregator);
  event RemovedAsset(address asset);

  struct Asset {
    address asset;
    uint8 assetType;
    address aggregator;
  }

  function addAsset(
    address asset,
    uint8 assetType,
    address aggregator
  ) external;

  function addAssets(Asset[] memory assets) external;

  function removeAsset(address asset) external;

  function priceAggregators(address asset) external view returns (address);

  function assetTypes(address asset) external view returns (uint8);

  function getAssetTypeAndAggregator(address asset) external view returns (uint8, address);

  function getUSDPrice(address asset) external view returns (uint256);
}
