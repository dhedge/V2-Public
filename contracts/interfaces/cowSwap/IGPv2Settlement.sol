// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;

interface IGPv2Settlement {
  /// @dev Sets a presignature for the specified order UID.
  ///
  /// @param orderUid The unique identifier of the order to pre-sign.
  /// @param signed True to set the order as tradable with pre-sign, false to
  /// false to unset it.
  function setPreSignature(bytes calldata orderUid, bool signed) external;

  /// @dev Invalidate onchain an order that has been signed offline.
  ///
  /// @param orderUid The unique identifier of the order that is to be made
  /// invalid after calling this function. The user that created the order
  /// must be the sender of this message. See [`extractOrderUidParams`]
  /// for details on orderUid.
  function invalidateOrder(bytes calldata orderUid) external;

  /// @dev Returns the pre-signature status for the specified order UID.
  ///
  /// @param orderUid The unique identifier of the order.
  /// @return The pre-signature marker value (PRE_SIGNED if pre-signed, 0 otherwise).
  function preSignature(bytes calldata orderUid) external view returns (uint256);

  /// @dev Returns the filled amount for the specified order UID.
  ///
  /// @param orderUid The unique identifier of the order.
  /// @return The filled amount (type(uint256).max if invalidated).
  function filledAmount(bytes calldata orderUid) external view returns (uint256);
}
