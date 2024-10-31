// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {IEasySwapperV2} from "../interfaces/IEasySwapperV2.sol";
import {IWithdrawalVault} from "../interfaces/IWithdrawalVault.sol";

library SwapperV2Helpers {
  function getUnrolledAssets(address _asset, address _dHedgeVault) internal view returns (address[] memory assets) {
    IWithdrawalVault.TrackedAsset[] memory trackedAssets = IEasySwapperV2(_asset).getTrackedAssets(_dHedgeVault);
    uint256 assetsLength = trackedAssets.length;
    assets = new address[](assetsLength);

    for (uint256 i; i < assetsLength; ++i) {
      assets[i] = trackedAssets[i].token;
    }
  }
}
