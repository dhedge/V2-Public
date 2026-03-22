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

import {IAddAssetCheckGuard} from "../../interfaces/guards/IAddAssetCheckGuard.sol";
import {IHasSupportedAsset} from "../../interfaces/IHasSupportedAsset.sol";
import {ClosedAssetGuard} from "./ClosedAssetGuard.sol";

/// @dev Asset type = 38
contract VirtualTokenAssetGuard is ClosedAssetGuard, IAddAssetCheckGuard {
  bool public override isAddAssetCheckGuard = true;

  function addAssetCheck(address, IHasSupportedAsset.Asset calldata) external pure override {
    revert("cannot add virtual token");
  }
}
