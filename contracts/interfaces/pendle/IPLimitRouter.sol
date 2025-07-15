// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

enum OrderType {
  SY_FOR_PT,
  PT_FOR_SY,
  SY_FOR_YT,
  YT_FOR_SY
}

struct Order {
  uint256 salt;
  uint256 expiry;
  uint256 nonce;
  OrderType orderType;
  address token;
  address YT;
  address maker;
  address receiver;
  uint256 makingAmount;
  uint256 lnImpliedRate;
  uint256 failSafeRate;
  bytes permit;
}

struct FillOrderParams {
  Order order;
  bytes signature;
  uint256 makingAmount;
}
