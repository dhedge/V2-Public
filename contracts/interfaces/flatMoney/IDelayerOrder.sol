// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IFlatcoinVault} from "./IFlatcoinVault.sol";

interface IDelayerOrder {
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
}
