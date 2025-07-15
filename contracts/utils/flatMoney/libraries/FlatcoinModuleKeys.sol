// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

library FlatcoinModuleKeys {
  bytes32 internal constant _STABLE_MODULE_KEY = bytes32("stableModule");
  bytes32 internal constant _POINTS_MODULE_KEY = bytes32("pointsModule");
  bytes32 internal constant _DELAYED_ORDER_KEY = bytes32("delayedOrder");
  bytes32 internal constant _LEVERAGE_MODULE_KEY = bytes32("leverageModule");
  bytes32 internal constant _ORACLE_MODULE_KEY = bytes32("oracleModule");
  bytes32 internal constant _ORDER_ANNOUNCEMENT_MODULE_KEY = bytes32("orderAnnouncementModule");
  bytes32 internal constant _ORDER_EXECUTION_MODULE_KEY = bytes32("orderExecutionModule");
}
