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
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {ERC20Guard} from "./ERC20Guard.sol";
import {NonDepositAssetGuard} from "./shared/NonDepositAssetGuard.sol";

/// @notice Asset guard for a nested vault, a vault whose token another vault holds: valued and
///         withdrawn like any ERC20, but never enabled as a deposit asset.
/// @dev Asset type = 1
// solhint-disable-next-line no-empty-blocks
contract NestedVaultAssetGuard is ERC20Guard, NonDepositAssetGuard {}
