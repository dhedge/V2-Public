// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.7.6;

import {IPoolFactory} from "../../../interfaces/IPoolFactory.sol";
import {IPoolManagerLogic} from "../../../interfaces/IPoolManagerLogic.sol";
import {IDhedgeNftTrackerStorage} from "../../../interfaces/tracker/IDhedgeNftTrackerStorage.sol";

abstract contract NftTrackerConsumerGuardBase {
  IDhedgeNftTrackerStorage public immutable nftTracker;
  bytes32 public immutable nftType;
  uint256 public immutable positionsLimit;

  constructor(address _nftTracker, bytes32 _nftType, uint256 _maxPositions) {
    require(_nftTracker != address(0), "invalid nftTracker");

    nftTracker = IDhedgeNftTrackerStorage(_nftTracker);
    nftType = _nftType;
    positionsLimit = _maxPositions;
  }

  /// @notice Retrieves the tokenIds owned by the specified poolLogic address
  function getOwnedTokenIds(address _poolLogic) public view returns (uint256[] memory tokenIds) {
    return nftTracker.getAllUintIds(nftType, _poolLogic);
  }

  /// @notice Checks if the specified tokenId is owned by the given pool
  function isValidOwnedTokenId(address _poolLogic, uint256 _tokenId) public view returns (bool isValid) {
    uint256[] memory tokenIds = getOwnedTokenIds(_poolLogic);
    for (uint256 i; i < tokenIds.length; ++i) {
      if (_tokenId == tokenIds[i]) {
        return true;
      }
    }
    return false;
  }

  function _accessControl(address _poolManagerLogic) internal view returns (address poolLogic) {
    poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();

    require(msg.sender == poolLogic && IPoolFactory(nftTracker.poolFactory()).isPool(poolLogic), "not pool logic");
  }
}
