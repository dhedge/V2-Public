// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IHasSupportedAsset} from "../../../interfaces/IHasSupportedAsset.sol";
import {IPoolLogic} from "../../../interfaces/IPoolLogic.sol";

library VelodromeHelpers {
  /// @dev If token (VELO/AERO) comes before LP asset in the list, it has been already processed separately upstream.
  ///      It means we need to transfer token's portion to the user during withdraw processing of LP asset.
  ///      If token comes after LP asset, no need to transfer as once claimed it will be processed downstream.
  ///      Example: after asset type 200 was set for reward token, it should always come before, but for some old vaults it might be different.
  function shouldTransferToken(
    address _pool,
    address _lpAsset,
    address _token
  ) internal view returns (bool shouldTransfer) {
    IHasSupportedAsset poolManagerLogic = IHasSupportedAsset(IPoolLogic(_pool).poolManagerLogic());

    // If it's not among supported assets, should always transfer
    if (!poolManagerLogic.isSupportedAsset(_token)) return true;

    IHasSupportedAsset.Asset[] memory supportedAssets = poolManagerLogic.getSupportedAssets();

    // Both addresses are guaranteed to be in supported assets at this point
    for (uint256 i; i < supportedAssets.length; ++i) {
      if (supportedAssets[i].asset == _lpAsset) {
        // Loop meets LP asset first, which means token comes after -> no need to transfer
        return false;
      } else if (supportedAssets[i].asset == _token) {
        // Loop meets token first, which means LP asset comes after -> need to transfer
        return true;
      }
    }
  }
}
