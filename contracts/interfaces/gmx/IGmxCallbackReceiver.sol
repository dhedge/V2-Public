// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {GmxEventUtils} from "../../utils/gmx/GmxEventUtils.sol";

interface IGmxCallbackReceiver {
  // v2.2 version
  function afterOrderExecution(
    bytes32 key,
    GmxEventUtils.EventLogData memory orderData,
    GmxEventUtils.EventLogData memory eventData
  ) external;
  function afterDepositExecution(
    bytes32 key,
    GmxEventUtils.EventLogData memory depositData,
    GmxEventUtils.EventLogData memory eventData
  ) external;
  function afterWithdrawalExecution(
    bytes32 key,
    GmxEventUtils.EventLogData memory withdrawalData,
    GmxEventUtils.EventLogData memory eventData
  ) external;
}
