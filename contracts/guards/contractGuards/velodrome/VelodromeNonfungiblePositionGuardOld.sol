// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import {ClosedContractGuard} from "../ClosedContractGuard.sol";
import {NftTrackerConsumerGuard} from "../shared/NftTrackerConsumerGuard.sol";

/// @title Transaction guard for Velodrome CL NonfungiblePositionManager contract (Old)
/// @dev This is needed because VelodromeCLAssetGuard is referencing this contract by calling `getOwnedTokenIds`
contract VelodromeNonfungiblePositionGuardOld is NftTrackerConsumerGuard, ClosedContractGuard {
  /// @param _nftTracker Address of the DhedgeNftTrackerStorage
  constructor(address _nftTracker) NftTrackerConsumerGuard(_nftTracker, keccak256("VELODROME_NFT_TYPE"), 1) {}
}
