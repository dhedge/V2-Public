// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IFlatcoinVault} from "./IFlatcoinVault.sol";

interface IDelayedOrder {
  enum OrderType {
    None,
    StableDeposit,
    StableWithdraw,
    LeverageOpen,
    LeverageClose,
    LeverageAdjust,
    LimitClose
  }

  struct Order {
    OrderType orderType;
    uint256 keeperFee;
    uint64 executableAtTime;
    bytes orderData;
  }

  function vault() external view returns (IFlatcoinVault vaultAddress);

  function announceStableDeposit(uint256 depositAmount, uint256 minAmountOut, uint256 keeperFee) external;

  function announceStableWithdraw(uint256 withdrawAmount, uint256 minAmountOut, uint256 keeperFee) external;

  function getAnnouncedOrder(address account) external view returns (Order memory order);

  function cancelExistingOrder(address account) external;

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

  function announceStableDepositFor(
    uint256 depositAmount,
    uint256 minAmountOut,
    uint256 keeperFee,
    address receiver
  ) external;

  function announceLeverageOpenFor(
    uint256 margin,
    uint256 additionalSize,
    uint256 maxFillPrice,
    uint256 keeperFee,
    address receiver
  ) external;
}
