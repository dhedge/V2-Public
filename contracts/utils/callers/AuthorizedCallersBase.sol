// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {EnumerableSet} from "@openzeppelin/v5/contracts/utils/structs/EnumerableSet.sol";

import {ICommonErrors} from "../../interfaces/ICommonErrors.sol";

/// @title AuthorizedCallersBase
/// @notice Abstract contract providing authorized callers logic with EnumerableSet storage
/// @dev Uses ERC-7201 namespaced storage to avoid slot collisions in upgradeable inheritors
abstract contract AuthorizedCallersBase {
  using EnumerableSet for EnumerableSet.AddressSet;

  // ============ ERC-7201 Storage ============

  /// @custom:storage-location erc7201:dhedge.storage.AuthorizedCallers
  struct AuthorizedCallersData {
    EnumerableSet.AddressSet callers;
  }

  // keccak256(abi.encode(uint256(keccak256("dhedge.storage.AuthorizedCallers")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant AUTHORIZED_CALLERS_STORAGE =
    0xcdb3375442d6adc6703c451a6331c3edfa079d72fb95411975cfc86bfe111600;

  // ============ Events ============

  event AuthorizedCallerSet(address indexed caller, bool authorized);

  // ============ Modifiers ============

  /// @notice Restricts function access to authorized callers
  modifier onlyAuthorizedCaller() {
    _checkAuthorizedCaller();
    _;
  }

  // ============ External View Functions ============

  /// @notice Whether `caller` is authorized
  function isAuthorizedCaller(address caller) public view virtual returns (bool) {
    AuthorizedCallersData storage $ = _getAuthorizedCallersStorage();
    return $.callers.contains(caller);
  }

  /// @notice List all authorized caller addresses
  function authorizedCallers() external view returns (address[] memory) {
    AuthorizedCallersData storage $ = _getAuthorizedCallersStorage();
    return $.callers.values();
  }

  // ============ Internal Functions ============

  /// @notice Check if caller is authorized
  /// @dev Internal function to save on contract size when modifier is used multiple times
  function _checkAuthorizedCaller() internal view {
    if (!isAuthorizedCaller(msg.sender)) revert ICommonErrors.UnauthorizedCaller(msg.sender);
  }

  /// @notice Add or remove an authorized caller
  /// @param caller Address to authorize or de-authorize
  /// @param authorized Whether to authorize or de-authorize
  function _setAuthorizedCaller(address caller, bool authorized) internal {
    if (caller == address(0)) revert ICommonErrors.ZeroAddress("caller");
    AuthorizedCallersData storage $ = _getAuthorizedCallersStorage();
    if (authorized) {
      $.callers.add(caller);
    } else {
      $.callers.remove(caller);
    }
    emit AuthorizedCallerSet(caller, authorized);
  }

  // ============ Private Functions ============

  function _getAuthorizedCallersStorage() private pure returns (AuthorizedCallersData storage $) {
    assembly {
      $.slot := AUTHORIZED_CALLERS_STORAGE
    }
  }
}
