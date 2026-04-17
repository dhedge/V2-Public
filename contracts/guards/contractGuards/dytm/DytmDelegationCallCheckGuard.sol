// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {TransientUint88Set} from "./TransientUint88Set.sol";

/// @title DytmDelegationCallCheckGuard
/// @notice Tracks delegation call state using EIP-1153 transient storage.
///         Enforces single-pool-at-a-time to block nested cross-pool delegation calls.
abstract contract DytmDelegationCallCheckGuard is TransientUint88Set {
  /// @dev The pool currently in a delegation call, or address(0) if none.
  ///      Single pool at a time — blocks nested cross-pool delegation calls.
  address private transient _ongoingDelegationCallPool;

  /// @dev Transient array base slots for market IDs queued during delegation calls
  bytes32 private constant _HF_ARRAY = keccak256("DytmDelegationCallCheckGuard.healthFactorCheckMarkets");
  bytes32 private constant _HF_DEDUP = keccak256("DytmDelegationCallCheckGuard.healthFactorCheckDedup");
  bytes32 private constant _AS_ARRAY = keccak256("DytmDelegationCallCheckGuard.activeMarkets");
  bytes32 private constant _AS_DEDUP = keccak256("DytmDelegationCallCheckGuard.activeMarketsDedup");

  function _checkAndSetDytmDelegateCall(address _poolLogic) internal virtual {
    require(_ongoingDelegationCallPool == address(0), "nested delegate call");
    _ongoingDelegationCallPool = _poolLogic;
  }

  function _checkIsOngoingDelegationCall(address _poolLogic) internal view returns (bool) {
    return _ongoingDelegationCallPool == _poolLogic;
  }

  function _clearOngoingDelegationCall(
    address _poolLogic
  ) internal returns (uint88[] memory marketsForHFCheck, uint88[] memory marketsForActiveStorage) {
    require(_ongoingDelegationCallPool == _poolLogic, "no ongoing delegate call");

    marketsForHFCheck = _readAndClearSet(_HF_ARRAY, _HF_DEDUP);
    marketsForActiveStorage = _readAndClearSet(_AS_ARRAY, _AS_DEDUP);

    _ongoingDelegationCallPool = address(0);
  }

  function _addMarketToCheckHFTransientStorage(address, uint88 _market) internal {
    _addToSet(_HF_ARRAY, _HF_DEDUP, _market);
  }

  function _addSupplyMarketForActiveMarketsTransientStorage(address, uint88 _market) internal {
    _addToSet(_AS_ARRAY, _AS_DEDUP, _market);
  }
}
