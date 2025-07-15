// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IGmxEvent} from "./IGmxEvent.sol";
import {Order} from "./IGmxOrder.sol";
import {IGmxDeposit} from "./IGmxDeposit.sol";
import {IGmxWithdrawal} from "./IGmxWithdrawal.sol";

interface IGmxCallbackReceiver {
  function afterOrderExecution(bytes32 key, Order.Props memory order, IGmxEvent.EventLogData memory eventData) external;
  function afterDepositExecution(
    bytes32 key,
    IGmxDeposit.Props memory deposit,
    IGmxEvent.EventLogData memory eventData
  ) external;
  function afterWithdrawalExecution(
    bytes32 key,
    IGmxWithdrawal.Props memory withdrawal,
    IGmxEvent.EventLogData memory eventData
  ) external;
}
