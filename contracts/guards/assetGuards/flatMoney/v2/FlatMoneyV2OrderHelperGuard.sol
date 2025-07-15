// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {FlatcoinModuleKeys} from "../../../../utils/flatMoney/libraries/FlatcoinModuleKeys.sol";
import {IOrderAnnouncementModule} from "../../../../interfaces/flatMoney/v2/IOrderAnnouncementModule.sol";
import {ILeverageModuleV2} from "../../../../interfaces/flatMoney/v2/ILeverageModuleV2.sol";
import {IStableModule} from "../../../../interfaces/flatMoney/IStableModule.sol";

abstract contract FlatMoneyV2OrderHelperGuard {
  /// @dev Types of orders which can appear on behalf of the vault are limited by the FlatMoneyOptionsOrderAnnouncementGuard AND
  ///      they include StableDeposit order and LeverageOpen order, due to public announceLeverageOpenFor and announceStableDepositFor functions.
  /// @param _vault Vault address
  /// @param _moduleAddress any Flat Money module address extended from ModuleUpgradeable
  /// @return noOrder True if there is no pending order
  function _hasNoBlockingOrder(address _vault, address _moduleAddress) internal view returns (bool noOrder) {
    IOrderAnnouncementModule orderAnnouncementModule = IOrderAnnouncementModule(
      ILeverageModuleV2(_moduleAddress).vault().moduleAddress(FlatcoinModuleKeys._ORDER_ANNOUNCEMENT_MODULE_KEY)
    );
    IOrderAnnouncementModule.Order memory announcedOrder = orderAnnouncementModule.getAnnouncedOrder(_vault);

    if (announcedOrder.orderType == IOrderAnnouncementModule.OrderType.None) {
      return true;
    }

    if (announcedOrder.orderType == IOrderAnnouncementModule.OrderType.StableDeposit) {
      IStableModule.AnnouncedStableDeposit memory stableDeposit = abi.decode(
        announcedOrder.orderData,
        (IStableModule.AnnouncedStableDeposit)
      );
      return stableDeposit.announcedBy != _vault;
    }

    if (announcedOrder.orderType == IOrderAnnouncementModule.OrderType.LeverageOpen) {
      ILeverageModuleV2.AnnouncedLeverageOpen memory leverageOpen = abi.decode(
        announcedOrder.orderData,
        (ILeverageModuleV2.AnnouncedLeverageOpen)
      );
      return leverageOpen.announcedBy != _vault;
    }

    return false;
  }
}
