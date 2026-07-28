// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

/// @dev Minimal Safe stub exposing `isOwner` for exercising the onlyOwnerOrSafeSigner path.
contract MockSafe {
  mapping(address => bool) private _owners;

  function setOwner(address _owner, bool _isOwner) external {
    _owners[_owner] = _isOwner;
  }

  function isOwner(address _owner) external view returns (bool) {
    return _owners[_owner];
  }
}
