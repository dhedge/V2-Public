// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {GmxClaimableCollateralTrackerLib} from "../utils/gmx/GmxClaimableCollateralTrackerLib.sol";

contract GmxTimeKeyViewer {
  function getAllClaimableCollateralTimeKeys(
    address nftTracker,
    GmxClaimableCollateralTrackerLib.ClaimableCollateralInfo memory params
  ) public view returns (uint256[] memory) {
    return GmxClaimableCollateralTrackerLib.getAllClaimableCollateralTimeKeys(nftTracker, params);
  }

  function getTotalClaimableAmount(
    address nftTracker,
    address dataStore,
    GmxClaimableCollateralTrackerLib.ClaimableCollateralInfo memory params
  ) public view returns (uint256) {
    return GmxClaimableCollateralTrackerLib.getTotalClaimableAmount(nftTracker, dataStore, params);
  }
}
