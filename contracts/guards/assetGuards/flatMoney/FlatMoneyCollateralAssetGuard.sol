// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IDelayedOrder} from "../../../interfaces/flatMoney/IDelayedOrder.sol";
import {ERC20Guard} from "../ERC20Guard.sol";

/// @notice AssetType = 22
contract FlatMoneyCollateralAssetGuard is ERC20Guard {
  IDelayedOrder public immutable delayedOrder;

  constructor(address _delayedOrder) {
    require(_delayedOrder != address(0), "invalid address");
    delayedOrder = IDelayedOrder(_delayedOrder);
  }

  function removeAssetCheck(address _pool, address _asset) public view override {
    super.removeAssetCheck(_pool, _asset);

    require(delayedOrder.getAnnouncedOrder(_pool).orderType == IDelayedOrder.OrderType.None, "order in progress");
  }
}
