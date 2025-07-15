// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IDelayedOrder} from "../../../interfaces/flatMoney/IDelayedOrder.sol";
import {ERC20Guard} from "../ERC20Guard.sol";

/// @notice AssetType = 22
contract FlatMoneyCollateralAssetGuard is ERC20Guard {
  IDelayedOrder public immutable orderModule;

  constructor(address _orderModule) {
    require(_orderModule != address(0), "invalid address");

    orderModule = IDelayedOrder(_orderModule);
  }

  function removeAssetCheck(address _pool, address _asset) public view virtual override {
    super.removeAssetCheck(_pool, _asset);

    require(orderModule.getAnnouncedOrder(_pool).orderType == IDelayedOrder.OrderType.None, "order in progress");
  }
}
