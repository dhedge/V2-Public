// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import {ClosedContractGuard} from "../ClosedContractGuard.sol";
import {DhedgeNftTrackerStorage} from "../../../utils/tracker/DhedgeNftTrackerStorage.sol";

/// @title Transaction guard for Velodrome CL NonfungiblePositionManager contract (Old)
/// @dev This is needed because VelodromeCLAssetGuard is referencing this contract by calling `getOwnedTokenIds`
contract VelodromeNonfungiblePositionGuardOld is ClosedContractGuard {
  bytes32 public constant NFT_TYPE = keccak256("VELODROME_NFT_TYPE");
  DhedgeNftTrackerStorage public immutable nftTracker;

  /// @param nftTrackerAddress Address of the DhedgeNftTrackerStorage
  constructor(address nftTrackerAddress) {
    nftTracker = DhedgeNftTrackerStorage(nftTrackerAddress);
  }

  /// @notice Retrieves the tokenIds owned by the specified poolLogic address
  /// @param poolLogic The address of the pool logic contract
  /// @return tokenIds An array of uint256 representing the tokenIds owned by the poolLogic address
  function getOwnedTokenIds(address poolLogic) public view returns (uint256[] memory tokenIds) {
    return nftTracker.getAllUintIds(NFT_TYPE, poolLogic);
  }
}
