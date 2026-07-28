// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;
pragma experimental ABIEncoderV2;

/// @notice Minimal interface for a Midas RedemptionVault (mToken redemption entrypoint).
/// @dev The custom-recipient overloads are intentionally omitted: dHEDGE guards only ever
///      allow the msg.sender variant so redeemed tokens / pending claims stay with the pool.
interface IMidasRedemptionVault {
  /// @notice Request status as defined by Midas `IManageableVault.RequestStatus`.
  ///         Encoded as uint8 across the ABI.
  enum RequestStatus {
    Pending, // 0
    Processed, // 1
    Canceled // 2
  }

  /// @notice Instantly redeems `amountMTokenIn` (18-decimals) of mToken to `tokenOut`, paid to msg.sender.
  function redeemInstant(address tokenOut, uint256 amountMTokenIn, uint256 minReceiveAmount) external;

  /// @notice Opens an asynchronous (curator-approved) redemption request for `amountMTokenIn` mToken.
  /// @return requestId The id assigned to the created request.
  function redeemRequest(address tokenOut, uint256 amountMTokenIn) external returns (uint256 requestId);

  /// @notice The mToken redeemed by this vault.
  function mToken() external view returns (address);

  /// @notice Monotonic counter; the next request will be assigned this value, so the most recent
  ///         request created in a transaction has id `currentRequestId() - 1`.
  function currentRequestId() external view returns (uint256);

  /// @notice Public getter for the request storage mapping.
  /// @dev `status` is the ABI encoding of `RequestStatus` (0 = Pending, 1 = Processed, 2 = Canceled).
  function redeemRequests(
    uint256 requestId
  )
    external
    view
    returns (
      address sender,
      address tokenOut,
      uint8 status,
      uint256 amountMToken,
      uint256 mTokenRate,
      uint256 tokenOutRate
    );
}
