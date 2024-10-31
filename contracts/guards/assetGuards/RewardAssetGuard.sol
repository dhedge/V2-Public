// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IHasSupportedAsset} from "../../interfaces/IHasSupportedAsset.sol";
import {IHasAssetInfo} from "../../interfaces/IHasAssetInfo.sol";
import {IPoolLogic} from "../../interfaces/IPoolLogic.sol";
import {IPoolFactory} from "../../interfaces/IPoolFactory.sol";
import {IAssetGuard} from "../../interfaces/guards/IAssetGuard.sol";
import {IGovernance} from "../../interfaces/IGovernance.sol";
import {ERC20Guard} from "./ERC20Guard.sol";

/// @notice AssetType = 200
/// @notice RewardAssetGuard is to ensure that linked assets are removed before removing the reward asset
contract RewardAssetGuard is ERC20Guard {
  struct RewardAssetSetting {
    address rewardToken;
    uint16[] linkedAssetTypes;
    uint16 underlyingAssetType; // for addtional base removeAssetCheck
  }

  // reward => AssetType => bool (is Reward for AssetType)
  mapping(address => mapping(uint16 => bool)) public linkedAssetTypesForReward;

  // reward => baseAssetType(for additional removeAssetCheck)
  mapping(address => uint16) public baseAssetType;

  constructor(RewardAssetSetting[] memory _rewardAssetSetting) {
    require(_rewardAssetSetting.length != 0, "empty _rewardAssetSetting");

    for (uint256 i = 0; i < _rewardAssetSetting.length; i++) {
      // only allow underlyingAssetType = 0 (ERC20) or 4 (LendingEnabledAssetGuard)
      require(
        _rewardAssetSetting[i].underlyingAssetType == 0 || _rewardAssetSetting[i].underlyingAssetType == 4,
        "underlyingAssetType not allowed"
      );
      address reward = _rewardAssetSetting[i].rewardToken;
      baseAssetType[reward] = _rewardAssetSetting[i].underlyingAssetType;
      uint16[] memory assetTypes = _rewardAssetSetting[i].linkedAssetTypes;
      for (uint256 j = 0; j < assetTypes.length; j++) {
        linkedAssetTypesForReward[reward][assetTypes[j]] = true;
      }
    }
  }

  function removeAssetCheck(address _pool, address _asset) public view override {
    address factory = IPoolLogic(_pool).factory();

    address governanceAddress = IPoolFactory(factory).governanceAddress();
    IAssetGuard baseAssetGuard = IAssetGuard(IGovernance(governanceAddress).assetGuards(baseAssetType[_asset])); // get Guard for base removeAssetCheck

    // 1. ensure base removeAssetCheck (from ERC20Guard or LendingEnabledAssetGuard)
    baseAssetGuard.removeAssetCheck(_pool, _asset);

    // 2. ensure linkedAssetTypesForReward are removed before removing the reward asset
    IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(IPoolLogic(_pool).poolManagerLogic());
    IHasSupportedAsset.Asset[] memory supportedAssets = poolManagerLogicAssets.getSupportedAssets();

    address asset;
    uint16 assetType;
    for (uint256 i; i < supportedAssets.length; ++i) {
      asset = supportedAssets[i].asset;
      assetType = IHasAssetInfo(factory).getAssetType(asset);

      require(!linkedAssetTypesForReward[_asset][assetType], "remove linked asset first");
    }
  }
}
