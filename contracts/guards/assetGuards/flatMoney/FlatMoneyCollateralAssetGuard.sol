// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IDelayerOrder} from "../../../interfaces/flatMoney/IDelayerOrder.sol";

import {ERC20Guard} from "../ERC20Guard.sol";

contract FlatMoneyCollateralAssetGuard is ERC20Guard {
  IDelayerOrder public immutable delayedOrder;

  constructor(address _delayedOrder) {
    require(_delayedOrder != address(0), "invalid address");
    delayedOrder = IDelayerOrder(_delayedOrder);
  }

  function removeAssetCheck(address _pool, address _asset) public view override {
    super.removeAssetCheck(_pool, _asset);

    require(delayedOrder.getAnnouncedOrder(_pool).orderType == IDelayerOrder.OrderType.None, "order in progress");
  }
}
