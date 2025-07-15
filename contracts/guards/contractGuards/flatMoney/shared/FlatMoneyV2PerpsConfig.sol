// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

library FlatMoneyV2PerpsConfig {
  bytes32 public constant NFT_TYPE = keccak256("FLAT_MONEY_V2_PERP_NFT");

  uint256 public constant MAX_POSITIONS = 1;

  uint256 public constant MAX_ALLOWED_LEVERAGE = 7e18; // 7x
}
