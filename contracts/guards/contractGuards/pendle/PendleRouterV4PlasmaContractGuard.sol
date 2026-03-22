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
// Copyright (c) 2026 dHEDGE DAO
//
// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IPActionMiscV3} from "../../../interfaces/pendle/IPActionMiscV3.sol";
import {IPYieldToken} from "../../../interfaces/pendle/IPYieldToken.sol";
import {IHasSupportedAsset} from "../../../interfaces/IHasSupportedAsset.sol";
import {PendlePTAssetGuard} from "../../assetGuards/pendle/PendlePTAssetGuard.sol";
import {PendleRouterV4ContractGuard} from "./PendleRouterV4ContractGuard.sol";

import "../../../interfaces/pendle/IPAllActionTypeV3.sol" as IPAllActionTypeV3;

// TODO: Add support for claiming YT rewards after expiry (expiry is in April)
/// @notice Whitelisting vaults was intentionally not implemented as the entire Plasma deployment is private with no external capital
contract PendleRouterV4PlasmaContractGuard is PendleRouterV4ContractGuard {
  constructor(
    address _slippageAccumulator,
    address _poolFactory
  ) PendleRouterV4ContractGuard(_slippageAccumulator, _poolFactory) {}

  function txGuard(
    address _poolManagerLogic,
    address _to,
    bytes memory _data
  ) public override returns (uint16 txType, bool isPublic) {
    address poolLogic = _accessControl(_poolManagerLogic);
    bytes4 method = getMethod(_data);

    // Slippage accumulator protection is intentionally disabled (intermediateSwapData is not set)
    // because this guard is designed for private guarded usage only.
    // Additionally, while we could track tokenIn spent vs PT received, some value goes to YT
    // which is not accounted for, causing the slippage system to incorrectly detect slippage.
    if (method == IPActionMiscV3.mintPyFromToken.selector) {
      (address receiver, address yt, , IPAllActionTypeV3.TokenInput memory input) = abi.decode(
        getParams(_data),
        (address, address, uint256, IPAllActionTypeV3.TokenInput)
      );

      require(receiver == poolLogic, "recipient is not pool");

      address pt = IPYieldToken(yt).PT();
      (, , address storedYt) = PendlePTAssetGuard(poolFactory.getAssetGuard(pt)).ptAssociatedData(pt);

      require(yt == storedYt, "invalid yt");

      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(pt), "pt not enabled");

      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(input.tokenIn), "unsupported input asset");

      require(input.swapData.swapType == IPAllActionTypeV3.SwapType.NONE, "only underlying");

      txType = uint16(TransactionType.BuyPendlePT);
    } else {
      (txType, isPublic) = super.txGuard(_poolManagerLogic, _to, _data);
    }
  }

  /// @notice Skip slippage tracking for mintPyFromToken since intermediateSwapData is not set
  function afterTxGuard(address _poolManagerLogic, address _to, bytes memory _data) public override {
    // Only call parent's afterTxGuard if intermediateSwapData was set (srcAsset != address(0))
    if (intermediateSwapData.srcAsset != address(0)) {
      super.afterTxGuard(_poolManagerLogic, _to, _data);
    }
  }
}
