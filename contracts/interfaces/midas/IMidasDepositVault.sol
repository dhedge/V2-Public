// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;

/// @notice Minimal interface for a Midas DepositVault (mToken minting entrypoint).
/// @dev The custom-recipient overloads are intentionally omitted: dHEDGE guards only ever
///      allow the msg.sender variant so freshly minted mTokens are credited to the pool itself.
interface IMidasDepositVault {
  /// @notice Instantly mints mToken to msg.sender for `amountToken` (18-decimals) of `tokenIn`.
  function depositInstant(address tokenIn, uint256 amountToken, uint256 minReceiveAmount, bytes32 referrerId) external;

  /// @notice The mToken minted by this vault.
  function mToken() external view returns (address);
}
