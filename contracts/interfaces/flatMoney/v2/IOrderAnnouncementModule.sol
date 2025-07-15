// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IFlatcoinVaultV2} from "./IFlatcoinVaultV2.sol";

interface IOrderAnnouncementModule {
  enum OrderType {
    None, // 0
    StableDeposit, // 1
    StableWithdraw, // 2
    LeverageOpen, // 3
    LeverageClose, // 4
    LeverageAdjust, // 5
    LimitClose // 6
  }

  struct Order {
    OrderType orderType;
    uint256 keeperFee;
    uint64 executableAtTime;
    bytes orderData;
  }

  function announceStableDeposit(uint256 depositAmount, uint256 minAmountOut, uint256 keeperFee) external;

  function announceStableWithdraw(uint256 withdrawAmount, uint256 minAmountOut, uint256 keeperFee) external;

  function announceLeverageOpenFor(
    uint256 margin,
    uint256 additionalSize,
    uint256 maxFillPrice,
    uint256 stopLossPrice,
    uint256 profitTakePrice,
    uint256 keeperFee,
    address receiver
  ) external;

  function announceLeverageOpen(
    uint256 margin,
    uint256 additionalSize,
    uint256 maxFillPrice,
    uint256 keeperFee
  ) external;

  function announceLeverageAdjust(
    uint256 tokenId,
    int256 marginAdjustment,
    int256 additionalSizeAdjustment,
    uint256 fillPrice,
    uint256 keeperFee
  ) external;

  function announceLeverageClose(uint256 tokenId, uint256 minFillPrice, uint256 keeperFee) external;

  function getAnnouncedOrder(address account) external view returns (Order memory order);

  function vault() external view returns (IFlatcoinVaultV2 vaultAddress);
}
