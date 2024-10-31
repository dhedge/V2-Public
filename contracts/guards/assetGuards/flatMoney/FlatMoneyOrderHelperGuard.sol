// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {FlatcoinModuleKeys} from "../../../utils/flatMoney/libraries/FlatcoinModuleKeys.sol";
import {IDelayedOrder} from "../../../interfaces/flatMoney/IDelayedOrder.sol";
import {ILeverageModule} from "../../../interfaces/flatMoney/ILeverageModule.sol";
import {IStableModule} from "../../../interfaces/flatMoney/IStableModule.sol";

abstract contract FlatMoneyOrderHelperGuard {
  /// @dev Types of orders which can appear on behalf of the vault are limited by the FlatMoneyDelayedOrderContractGuard AND
  ///      they include StableDeposit order and LeverageOpen order, due to public announceLeverageOpenFor and announceStableDepositFor functions.
  /// @param _vault Vault address
  /// @param _moduleAddress any Flat Money module address extended from ModuleUpgradeable
  /// @return noOrder True if there is no pending order
  function _hasNoBlockingOrder(address _vault, address _moduleAddress) internal view returns (bool noOrder) {
    IDelayedOrder delayedOrder = IDelayedOrder(
      IDelayedOrder(_moduleAddress).vault().moduleAddress(FlatcoinModuleKeys._DELAYED_ORDER_KEY)
    );
    IDelayedOrder.Order memory announcedOrder = delayedOrder.getAnnouncedOrder(_vault);

    if (announcedOrder.orderType == IDelayedOrder.OrderType.None) {
      return true;
    }

    if (announcedOrder.orderType == IDelayedOrder.OrderType.StableDeposit) {
      IStableModule.AnnouncedStableDeposit memory stableDeposit = abi.decode(
        announcedOrder.orderData,
        (IStableModule.AnnouncedStableDeposit)
      );
      return stableDeposit.announcedBy != _vault;
    }

    if (announcedOrder.orderType == IDelayedOrder.OrderType.LeverageOpen) {
      ILeverageModule.AnnouncedLeverageOpen memory leverageOpen = abi.decode(
        announcedOrder.orderData,
        (ILeverageModule.AnnouncedLeverageOpen)
      );
      return leverageOpen.announcedBy != _vault;
    }

    return false;
  }
}
