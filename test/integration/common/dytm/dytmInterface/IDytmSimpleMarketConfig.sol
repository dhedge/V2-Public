// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

interface IDytmSimpleMarketConfig {
  struct AssetConfig {
    address asset;
    bool isBorrowable;
  }
  function addSupportedAssets(AssetConfig[] calldata assetsConfig) external;
  function owner() external view returns (address);
}
