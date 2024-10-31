//SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

interface IAsyncOrderSettlementPythModule {
  /**
   * @notice Settles an offchain order using the offchain retrieved data from pyth.
   * @param accountId The account id to settle the order
   */
  function settleOrder(uint128 accountId) external;
}
