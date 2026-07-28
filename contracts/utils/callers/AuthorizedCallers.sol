// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/v5/contracts/access/Ownable.sol";

import {AuthorizedCallersBase} from "./AuthorizedCallersBase.sol";

/// @title AuthorizedCallers
/// @notice Non-upgradeable contract providing authorized callers functionality
/// @dev Inheriting contracts must pass owner address to constructor
abstract contract AuthorizedCallers is Ownable, AuthorizedCallersBase {
  constructor(address _owner) Ownable(_owner) {}

  // ============ Owner Functions ============

  /// @notice Authorize or de-authorize a caller
  /// @param caller Address to authorize or de-authorize
  /// @param authorized Whether to authorize or de-authorize
  function setAuthorizedCaller(address caller, bool authorized) external onlyOwner {
    _setAuthorizedCaller(caller, authorized);
  }
}
