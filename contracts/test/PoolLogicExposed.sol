// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {PoolLogic} from "../PoolLogic.sol";

contract PoolLogicExposed is PoolLogic {
  function _calculateCooldownExposed(
    uint256 _currentBalance,
    uint256 _liquidityMinted,
    uint256 _newCooldown,
    uint256 _lastCooldown,
    uint256 _lastDepositTime,
    uint256 _blockTimestamp
  ) external pure returns (uint256 cooldown) {
    cooldown = _calculateCooldown(
      _currentBalance,
      _liquidityMinted,
      _newCooldown,
      _lastCooldown,
      _lastDepositTime,
      _blockTimestamp
    );
  }
}
