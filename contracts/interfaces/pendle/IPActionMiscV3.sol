// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import "./IPAllActionTypeV3.sol";

/// Refer to IPAllActionTypeV3.sol for details on the parameters
interface IPActionMiscV3 {
  function exitPreExpToToken(
    address receiver,
    address market,
    uint256 netPtIn,
    uint256 netYtIn,
    uint256 netLpIn,
    TokenOutput calldata output,
    LimitOrderData calldata limit
  ) external returns (uint256 netTokenOut, ExitPreExpReturnParams memory params);

  function exitPreExpToSy(
    address receiver,
    address market,
    uint256 netPtIn,
    uint256 netYtIn,
    uint256 netLpIn,
    uint256 minSyOut,
    LimitOrderData calldata limit
  ) external returns (ExitPreExpReturnParams memory params);

  function exitPostExpToToken(
    address receiver,
    address market,
    uint256 netPtIn,
    uint256 netLpIn,
    TokenOutput calldata output
  ) external returns (uint256 netTokenOut, ExitPostExpReturnParams memory params);

  function exitPostExpToSy(
    address receiver,
    address market,
    uint256 netPtIn,
    uint256 netLpIn,
    uint256 minSyOut
  ) external returns (ExitPostExpReturnParams memory params);

  function redeemPyToToken(
    address receiver,
    address YT,
    uint256 netPyIn,
    TokenOutput calldata output
  ) external returns (uint256 netTokenOut, uint256 netSyInterm);
}
