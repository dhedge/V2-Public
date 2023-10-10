// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

interface IFactory {
  function getAssetHandler() external view returns (address assetHandler);

  function getAssetPrice(address asset) external view returns (uint256 price);

  function isPool(address pool) external view returns (bool);

  function isValidAsset(address asset) external view returns (bool);
}
