// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import "./IPAllActionTypeV3.sol";

/// Refer to IPAllActionTypeV3.sol for details on the parameters
interface IPActionSwapPTV3 {
  function swapExactTokenForPt(
    address receiver,
    address market,
    uint256 minPtOut,
    ApproxParams calldata guessPtOut,
    TokenInput calldata input,
    LimitOrderData calldata limit
  ) external payable returns (uint256 netPtOut, uint256 netSyFee, uint256 netSyInterm);

  function swapExactSyForPt(
    address receiver,
    address market,
    uint256 exactSyIn,
    uint256 minPtOut,
    ApproxParams calldata guessPtOut,
    LimitOrderData calldata limit
  ) external returns (uint256 netPtOut, uint256 netSyFee);

  function swapExactPtForToken(
    address receiver,
    address market,
    uint256 exactPtIn,
    TokenOutput calldata output,
    LimitOrderData calldata limit
  ) external returns (uint256 netTokenOut, uint256 netSyFee, uint256 netSyInterm);

  function swapExactPtForSy(
    address receiver,
    address market,
    uint256 exactPtIn,
    uint256 minSyOut,
    LimitOrderData calldata limit
  ) external returns (uint256 netSyOut, uint256 netSyFee);
}
