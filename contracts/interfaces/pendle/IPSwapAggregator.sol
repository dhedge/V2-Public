// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

struct SwapData {
  SwapType swapType;
  address extRouter;
  bytes extCalldata;
  bool needScale;
}

enum SwapType {
  NONE,
  KYBERSWAP,
  ODOS,
  // ETH_WETH not used in Aggregator
  ETH_WETH,
  OKX,
  ONE_INCH,
  RESERVE_1,
  RESERVE_2,
  RESERVE_3,
  RESERVE_4,
  RESERVE_5
}
