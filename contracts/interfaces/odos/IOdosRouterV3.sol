// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IOdosRouterV2} from "./IOdosRouterV2.sol";

interface IOdosRouterV3 is IOdosRouterV2 {
  /// @dev Holds all information for a given referral
  struct SwapReferralInfo {
    uint64 code;
    uint64 fee;
    address feeRecipient;
  }

  function swap(
    SwapTokenInfo memory tokenInfo,
    bytes calldata pathDefinition,
    address executor,
    SwapReferralInfo memory referralInfo
  ) external payable returns (uint256 amountOut);
}
