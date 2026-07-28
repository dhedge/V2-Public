//
//        __  __    __  ________  _______    ______   ________
//       /  |/  |  /  |/        |/       \  /      \ /        |
//   ____$$ |$$ |  $$ |$$$$$$$$/ $$$$$$$  |/$$$$$$  |$$$$$$$$/
//  /    $$ |$$ |__$$ |$$ |__    $$ |  $$ |$$ | _$$/ $$ |__
// /$$$$$$$ |$$    $$ |$$    |   $$ |  $$ |$$ |/    |$$    |
// $$ |  $$ |$$$$$$$$ |$$$$$/    $$ |  $$ |$$ |$$$$ |$$$$$/
// $$ \__$$ |$$ |  $$ |$$ |_____ $$ |__$$ |$$ \__$$ |$$ |_____
// $$    $$ |$$ |  $$ |$$       |$$    $$/ $$    $$/ $$       |
//  $$$$$$$/ $$/   $$/ $$$$$$$$/ $$$$$$$/   $$$$$$/  $$$$$$$$/
//
// dHEDGE DAO - https://dhedge.org
//
// Copyright (c) 2025 dHEDGE DAO
//
// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IOdosRouterV2} from "../../../interfaces/odos/IOdosRouterV2.sol";
import {OdosSharedContractGuard} from "./OdosSharedContractGuard.sol";

/// @notice Contract guard contract for OdosRouterV2
contract OdosV2ContractGuard is OdosSharedContractGuard {
  // V2 fee/beneficiary come from the router's permissionless referral registry; forbid fee-bearing codes.
  uint256 internal constant REFERRAL_WITH_FEE_THRESHOLD = 1 << 31;

  constructor(
    address _slippageAccumulator
  ) OdosSharedContractGuard(_slippageAccumulator, IOdosRouterV2.swap.selector) {}

  function txGuard(
    address _poolManagerLogic,
    address _to,
    bytes memory _data
  ) external override returns (uint16 txType, bool) {
    address poolLogic = _accessControl(_poolManagerLogic);
    bytes4 method = getMethod(_data);

    if (method == IOdosRouterV2.swap.selector) {
      (IOdosRouterV2.SwapTokenInfo memory tokenInfo, , , uint32 referralCode) = abi.decode(
        getParams(_data),
        (IOdosRouterV2.SwapTokenInfo, bytes, address, uint32)
      );
      txType = _verifySwap(tokenInfo, _poolManagerLogic, poolLogic);
      _verifyReferralCode(referralCode);
    } else if (method == IOdosRouterV2.swapCompact.selector) {
      (bool success, bytes memory swapData) = address(this).staticcall(
        abi.encodePacked(this._decodeCompactSwap.selector, _to, _data)
      );
      require(success, "decodeCompactSwap failed");
      (IOdosRouterV2.SwapTokenInfo memory tokenInfo, uint256 referralCode) = abi.decode(
        swapData,
        (IOdosRouterV2.SwapTokenInfo, uint256)
      );
      txType = _verifySwap(tokenInfo, _poolManagerLogic, poolLogic);
      _verifyReferralCode(referralCode);
    }

    return (txType, false);
  }

  /// @dev Compact staticcall target: reuse the shared walk for tokenInfo + referralPos, then load the
  ///      referralCode exactly as OdosRouterV2.swapCompact does.
  ///      https://github.com/odos-xyz/odos-router-v2/blob/main/contracts/OdosRouterV2.sol#L185
  function _decodeCompactSwap()
    public
    view
    returns (IOdosRouterV2.SwapTokenInfo memory tokenInfo, uint256 referralCode)
  {
    uint256 pos;
    (tokenInfo, pos) = _decodeCompactCalldata();
    assembly {
      referralCode := shr(224, calldataload(pos))
    }
  }

  /// @dev Router charges a referral fee only for codes above this threshold; require at or below.
  ///      https://github.com/odos-xyz/odos-router-v2/blob/main/contracts/OdosRouterV2.sol#L335
  function _verifyReferralCode(uint256 _code) private pure {
    require(_code <= REFERRAL_WITH_FEE_THRESHOLD, "referral fee not allowed");
  }
}
