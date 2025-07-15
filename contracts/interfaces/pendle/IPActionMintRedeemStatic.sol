// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable
pragma solidity 0.7.6;

/// @dev This is not a full interface
interface IPActionMintRedeemStatic {
  function redeemPyToSyStatic(address YT, uint256 netPYToRedeem) external view returns (uint256 netSyOut);

  function redeemPyToTokenStatic(
    address YT,
    uint256 netPYToRedeem,
    address tokenOut
  ) external view returns (uint256 netTokenOut);

  function redeemSyToTokenStatic(
    address SY,
    address tokenOut,
    uint256 netSyIn
  ) external view returns (uint256 netTokenOut);
}
