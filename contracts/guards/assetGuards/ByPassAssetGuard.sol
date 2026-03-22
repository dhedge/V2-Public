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
// Copyright (c) dHEDGE DAO
//
// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {ERC20Guard} from "./ERC20Guard.sol";

/// @title Modified ERC20Guard
/// @dev Asset type = 999
/// @dev A special guard which can be used to rescue stuck tokens in a pool with non-transferable assets.
///      The non-transferable asset should have this as their guard.
contract ByPassAssetGuard is ERC20Guard {
  /// @notice Returns the balance of the managed asset
  /// @dev This returns 0 as we don't want the withdrawProcessing to be halted
  ///      due to positive balance of the asset.
  /// @return balance The asset balance of given pool
  function getBalance(address, address) public pure override returns (uint256 balance) {
    return 0;
  }
}
