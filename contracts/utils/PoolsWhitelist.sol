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
// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {SafeSignerAccess} from "./SafeSignerAccess.sol";

/// @title PoolsWhitelist
/// @notice Owner-managed whitelist of pools, for guards that gate an integration to
///         protocol-chosen vaults. Seeded at deployment and adjustable afterwards by the owner —
///         or, when the owner is a Safe, by any of its signers (`SafeSignerAccess`).
abstract contract PoolsWhitelist is Ownable, SafeSignerAccess {
  struct WhitelistSetting {
    address poolLogic;
    bool whitelisted;
  }

  /// @notice Pools allowed to use the integration protected by the inheriting guard.
  mapping(address => bool) public poolsWhitelist;

  event PoolWhitelistSet(address poolLogic, bool whitelisted);

  constructor(address[] memory _whitelistedPools) {
    for (uint256 i; i < _whitelistedPools.length; ++i) {
      _setPoolWhitelisted(_whitelistedPools[i], true);
    }
  }

  function setPoolsWhitelist(WhitelistSetting[] calldata _settings) external onlyOwnerOrSafeSigner(owner()) {
    for (uint256 i; i < _settings.length; ++i) {
      _setPoolWhitelisted(_settings[i].poolLogic, _settings[i].whitelisted);
    }
  }

  function _setPoolWhitelisted(address _poolLogic, bool _whitelisted) private {
    require(_poolLogic != address(0), "invalid pool");

    poolsWhitelist[_poolLogic] = _whitelisted;

    emit PoolWhitelistSet(_poolLogic, _whitelisted);
  }
}
