// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;

import {ISafe} from "../interfaces/ISafe.sol";

/// @title SafeSignerAccess
/// @notice Abstract contract that allows any Safe owner (as returned by `ISafe.isOwner`) to call restricted functions.
/// @dev The `onlyOwnerOrSafeSigner` modifier takes the owner address as a parameter.
///      If the owner is a Safe, any account registered as a Safe owner can pass the check.
///      If the owner is not a Safe (e.g., an EOA), only the owner address itself is accepted.
abstract contract SafeSignerAccess {
  modifier onlyOwnerOrSafeSigner(address _owner) {
    _checkOwnerOrSafeSigner(_owner);
    _;
  }

  function _checkOwnerOrSafeSigner(address _owner) internal view {
    if (msg.sender == _owner) return;

    // Try to check if the owner is a Safe and if msg.sender is one of its owners.
    // Note: If `_owner` is an EOA (no code), the external call reverts with
    // "function call to a non-contract account" which is NOT caught by try/catch
    // (the extcodesize check runs before the CALL opcode, outside the try/catch boundary).
    // This is safe because the `msg.sender == _owner` check above already handles the EOA owner case.
    try ISafe(_owner).isOwner(msg.sender) returns (bool isOwner_) {
      require(isOwner_, "not owner or Safe owner");
    } catch {
      // Owner is not a Safe (or doesn't implement isOwner), fall back to strict owner check.
      revert("not owner or Safe owner");
    }
  }
}
