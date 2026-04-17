// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/v5/contracts/access/Ownable.sol";

import {AuthorizedKeepersBase} from "./AuthorizedKeepersBase.sol";

/// @title AuthorizedKeepers
/// @notice Non-upgradeable contract providing authorized keepers functionality
/// @dev Inheriting contracts must pass owner address to constructor
abstract contract AuthorizedKeepers is Ownable, AuthorizedKeepersBase {
  constructor(address _owner) Ownable(_owner) {}

  // ============ Owner Functions ============

  /// @notice Add an authorized keeper
  /// @param keeper_ Address to authorize
  function addAuthorizedKeeper(address keeper_) external onlyOwner {
    _addAuthorizedKeeper(keeper_);
  }

  /// @notice Remove an authorized keeper
  /// @param keeper_ Address to de-authorize
  function removeAuthorizedKeeper(address keeper_) external onlyOwner {
    _removeAuthorizedKeeper(keeper_);
  }
}
