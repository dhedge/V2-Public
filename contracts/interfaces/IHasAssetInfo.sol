// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;

interface IHasAssetInfo {
  function isValidAsset(address asset) external view returns (bool isValid);

  function getAssetPrice(address asset) external view returns (uint256 price);

  function getAssetPriceWithTime(
    address asset
  ) external view returns (uint256 price, uint256 updatedAt, uint256 maxPriceAge);

  function getAssetType(address asset) external view returns (uint16 assetType);

  function getMaximumSupportedAssetCount() external view returns (uint256 count);
}
