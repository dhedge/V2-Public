// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IHasSupportedAsset} from "../../interfaces/IHasSupportedAsset.sol";
import {IHasAssetInfo} from "../../interfaces/IHasAssetInfo.sol";
import {IPoolLogic} from "../../interfaces/IPoolLogic.sol";
import {ERC20Guard} from "./ERC20Guard.sol";

/// @notice AssetType = 200
/// @notice RewardAssetGuard is to ensure that linked assets are removed before removing the reward asset
contract RewardAssetGuard is ERC20Guard {
  // Can use either list of asset types OR list of asset addresses for more flexibility and control OR both
  struct RewardAssetSetting {
    address rewardToken;
    uint16[] linkedAssetTypes;
    address[] linkedAssets;
  }

  // reward => AssetType => bool (is Reward for AssetType)
  mapping(address => mapping(uint16 => bool)) public linkedAssetTypesForReward;

  // reward => asset => bool (is Reward for Asset)
  mapping(address => mapping(address => bool)) public linkedAssets;

  constructor(RewardAssetSetting[] memory _rewardAssetSetting) {
    require(_rewardAssetSetting.length != 0, "empty _rewardAssetSetting");

    for (uint256 i = 0; i < _rewardAssetSetting.length; i++) {
      uint16[] memory assetTypes = _rewardAssetSetting[i].linkedAssetTypes;
      for (uint256 j = 0; j < assetTypes.length; j++) {
        linkedAssetTypesForReward[_rewardAssetSetting[i].rewardToken][assetTypes[j]] = true;
      }

      address[] memory assets = _rewardAssetSetting[i].linkedAssets;
      for (uint256 j = 0; j < assets.length; j++) {
        linkedAssets[_rewardAssetSetting[i].rewardToken][assets[j]] = true;
      }
    }
  }

  function removeAssetCheck(address _pool, address _asset) public view override {
    // 1. ensure base removeAssetCheck (from ERC20Guard)
    super.removeAssetCheck(_pool, _asset);

    address factory = IPoolLogic(_pool).factory();
    // 2. ensure linkedAssetTypesForReward are removed before removing the reward asset
    IHasSupportedAsset.Asset[] memory supportedAssets = IHasSupportedAsset(IPoolLogic(_pool).poolManagerLogic())
      .getSupportedAssets();

    uint16 assetType;
    for (uint256 i; i < supportedAssets.length; ++i) {
      require(!linkedAssets[_asset][supportedAssets[i].asset], "remove linked asset first");

      assetType = IHasAssetInfo(factory).getAssetType(supportedAssets[i].asset);

      require(!linkedAssetTypesForReward[_asset][assetType], "remove linked asset first");
    }
  }
}
