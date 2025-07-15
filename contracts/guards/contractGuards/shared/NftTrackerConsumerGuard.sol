// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {ITransactionTypes} from "../../../interfaces/ITransactionTypes.sol";
import {DhedgeNftTrackerStorage} from "../../../utils/tracker/DhedgeNftTrackerStorage.sol";
import {TxDataUtils} from "../../../utils/TxDataUtils.sol";

abstract contract NftTrackerConsumerGuard is TxDataUtils, ITransactionTypes {
  DhedgeNftTrackerStorage public immutable nftTracker;
  bytes32 public immutable nftType;
  uint256 public immutable positionsLimit;

  constructor(address _nftTracker, bytes32 _nftType, uint256 _maxPositions) {
    require(_nftTracker != address(0), "invalid nftTracker");

    nftTracker = DhedgeNftTrackerStorage(_nftTracker);
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
}
