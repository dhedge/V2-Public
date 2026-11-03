//
//    ===========  ======     ======         =         ====          ====   =========    ==========   ==========
//   ==        ==    ===        ==          ===          ===         ===     ==    ==     ===    ==     ==   ====
// ===          =    ===        ==         = ===         ====       ====     ==    ==     ===           ==    ===
// ====              =============        =   ===        = ===    == ===     ========     ========      =======
// ====              ===        ==       =========       =  ===  ==  ===     ==    ===    ===    =      ==  ===
// ==                ===        ==      =       ===      =   === ==  ===     ==     ===   ===           ==   ===
//   ===       ==    ===        ==     ==        ====    =    ===    ===     ==     ==    ===     ==    ==     ====
//     ==========  ======     ====== =====       ===== ====    ==    ====  ==========    ===========  ======     ====
//
// Chamber Finance - https://chamberfi.com
//
// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;
pragma abicoder v2;

import {IHasSupportedAsset} from "../../../interfaces/IHasSupportedAsset.sol";
import {AddAssetCheckGuard} from "./AddAssetCheckGuard.sol";

/// @notice Base for asset guards whose asset can be held by a pool but never enabled as a deposit asset.
/// @dev Overrides that add further checks call `super._addAssetCheck` first.
abstract contract NonDepositAssetGuard is AddAssetCheckGuard {
  function _addAssetCheck(address, IHasSupportedAsset.Asset calldata _asset) internal view virtual override {
    require(!_asset.isDeposit, "deposit not supported");
  }
}
