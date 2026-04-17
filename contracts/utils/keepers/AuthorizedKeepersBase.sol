// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title AuthorizedKeepersBase
/// @notice Abstract contract providing core authorized keepers logic
/// @dev Inherit and add owner-restricted external functions in child contracts
abstract contract AuthorizedKeepersBase {
  // ============ State ============

  /// @notice Mapping of authorized keeper addresses
  mapping(address keeper => bool isAuthorized) public isAuthorizedKeeper;

  // ============ Events ============

  event AuthorizedKeeperAdded(address indexed keeper);
  event AuthorizedKeeperRemoved(address indexed keeper);

  // ============ Errors ============

  error NotAuthorizedKeeper(address caller);

  // ============ Modifiers ============

  /// @notice Restricts function access to authorized keepers
  modifier onlyAuthorizedKeeper() {
    _checkAuthorizedKeeper();
    _;
  }

  // ============ Internal Functions ============

  /// @notice Check if caller is an authorized keeper
  /// @dev Internal function to save on contract size when modifier is used multiple times
  function _checkAuthorizedKeeper() internal view {
    if (!isAuthorizedKeeper[msg.sender]) revert NotAuthorizedKeeper(msg.sender);
  }

  /// @notice Internal function to add an authorized keeper
  /// @param keeper_ Address to authorize
  function _addAuthorizedKeeper(address keeper_) internal {
    isAuthorizedKeeper[keeper_] = true;
    emit AuthorizedKeeperAdded(keeper_);
  }

  /// @notice Internal function to remove an authorized keeper
  /// @param keeper_ Address to de-authorize
  function _removeAuthorizedKeeper(address keeper_) internal {
    isAuthorizedKeeper[keeper_] = false;
    emit AuthorizedKeeperRemoved(keeper_);
  }
}
