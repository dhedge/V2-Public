// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;

/// @notice Minimal interface for Permit2 nonce checking
interface IPermit2 {
  /// @notice Returns the bitmap of used nonces for a given address and word position
  /// @param owner The address to check nonces for
  /// @param wordPos The word position in the bitmap
  /// @return The bitmap value at that position
  function nonceBitmap(address owner, uint256 wordPos) external view returns (uint256);
}
