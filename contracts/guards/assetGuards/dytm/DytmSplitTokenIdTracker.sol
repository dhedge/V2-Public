// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IPoolManagerLogic} from "../../../interfaces/IPoolManagerLogic.sol";
import {IPoolFactory} from "../../../interfaces/IPoolFactory.sol";

/// @title Dytm Split Token ID Tracker
/// @notice Abstract contract for tracking DYTM split account positions created during withdrawals
/// @dev Extends this to track isolated account IDs and their market IDs from account splitting operations
abstract contract DytmSplitTokenIdTracker {
  struct SplitPosition {
    uint256 tokenId; // isolated account ID
    uint88 marketId; // DYTM market ID
  }

  /// @dev Split positions tracked per recipient
  mapping(address => SplitPosition[]) internal splitPositions;

  /// @notice Access control check for pool operations
  /// @param poolManagerLogic Address of the pool manager logic
  /// @param poolFactory Address of the pool factory
  /// @return poolLogic Address of the pool logic
  function _accessControl(address poolManagerLogic, address poolFactory) internal view returns (address poolLogic) {
    poolLogic = IPoolManagerLogic(poolManagerLogic).poolLogic();
    require(msg.sender == poolLogic && IPoolFactory(poolFactory).isPool(poolLogic), "not pool logic");
  }

  /// @notice Reset all split positions for a recipient
  /// @dev Clears previously tracked split positions, called before new withdrawal processing
  /// @param _to Address of the recipient whose split positions should be reset
  function _resetSplitTokenIds(address _to) internal {
    delete splitPositions[_to];
  }

  /// @notice Add a new split position for a recipient
  /// @dev Creates an isolated account ID from the DYTM account counter and records the market ID
  /// @param _to Address of the recipient
  /// @param _newAccountIdCount New account ID count from DYTM Office
  /// @param _marketId DYTM market ID for the split position
  /// @return newAccountId The newly created isolated account ID (shifted left by 160 bits)
  function _addSplitTokenId(
    address _to,
    uint256 _newAccountIdCount,
    uint88 _marketId
  ) internal returns (uint256 newAccountId) {
    newAccountId = uint256(_newAccountIdCount << 160); // Shift to create isolated account ID
    splitPositions[_to].push(SplitPosition({tokenId: newAccountId, marketId: _marketId}));
  }

  /// @notice Get all split positions for a recipient
  /// @dev Returns all isolated account IDs and their market IDs that were split during withdrawal
  /// @param _to Address of the recipient
  /// @return positions Array of split positions (tokenId + marketId)
  function getSplitPositions(address _to) external view returns (SplitPosition[] memory) {
    return splitPositions[_to];
  }
}
