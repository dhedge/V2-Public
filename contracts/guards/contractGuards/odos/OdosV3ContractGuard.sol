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
import {IOdosRouterV3} from "../../../interfaces/odos/IOdosRouterV3.sol";
import {OdosSharedContractGuard} from "./OdosSharedContractGuard.sol";

/// @notice Contract guard contract for OdosRouterV3
contract OdosV3ContractGuard is OdosSharedContractGuard {
  constructor(
    address _slippageAccumulator
  ) OdosSharedContractGuard(_slippageAccumulator, IOdosRouterV3.swap.selector) {}

  function txGuard(
    address _poolManagerLogic,
    address _to,
    bytes memory _data
  ) external override returns (uint16 txType, bool) {
    address poolLogic = _accessControl(_poolManagerLogic);
    bytes4 method = getMethod(_data);

    if (method == IOdosRouterV3.swap.selector) {
      (IOdosRouterV2.SwapTokenInfo memory tokenInfo, , , IOdosRouterV3.SwapReferralInfo memory referralInfo) = abi
        .decode(getParams(_data), (IOdosRouterV2.SwapTokenInfo, bytes, address, IOdosRouterV3.SwapReferralInfo));
      txType = _verifySwap(tokenInfo, _poolManagerLogic, poolLogic);
      _verifyReferral(referralInfo.fee);
    } else if (method == IOdosRouterV2.swapCompact.selector) {
      (bool success, bytes memory swapData) = address(this).staticcall(
        abi.encodePacked(this._decodeCompactSwap.selector, _to, _data)
      );
      require(success, "decodeCompactSwap failed");
      (IOdosRouterV2.SwapTokenInfo memory tokenInfo, IOdosRouterV3.SwapReferralInfo memory referralInfo) = abi.decode(
        swapData,
        (IOdosRouterV2.SwapTokenInfo, IOdosRouterV3.SwapReferralInfo)
      );
      txType = _verifySwap(tokenInfo, _poolManagerLogic, poolLogic);
      _verifyReferral(referralInfo.fee);
    }

    return (txType, false);
  }

  /// @dev Compact staticcall target: reuse the shared walk for tokenInfo + referralPos, then load the referral
  ///      block exactly as OdosRouterV3.swapCompact does.
  ///      https://github.com/odos-xyz/odos-router-v3/blob/main/contracts/OdosRouterV3.sol#L119
  function _decodeCompactSwap()
    public
    view
    returns (IOdosRouterV2.SwapTokenInfo memory tokenInfo, IOdosRouterV3.SwapReferralInfo memory referralInfo)
  {
    uint256 pos;
    (tokenInfo, pos) = _decodeCompactCalldata();
    assembly {
      let referralCode := shr(192, calldataload(pos))
      pos := add(pos, 8)
      mstore(referralInfo, referralCode)

      let feeStatus := shr(248, calldataload(pos))
      pos := add(pos, 1)

      if feeStatus {
        let referralFee := shr(192, calldataload(pos))
        pos := add(pos, 8)
        mstore(add(referralInfo, 0x20), referralFee)

        let referralBeneficiary := shr(96, calldataload(pos))
        pos := add(pos, 20)
        mstore(add(referralInfo, 0x40), referralBeneficiary)
      }
    }
  }

  /// @dev V3 takes the referral fee inline from the swap output (no registry); forbid any fee.
  function _verifyReferral(uint64 _fee) private pure {
    require(_fee == 0, "referral fee not allowed");
  }
}
