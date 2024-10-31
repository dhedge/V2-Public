// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

interface IAsyncOrderModule {
  struct OrderCommitmentRequest {
    uint128 marketId;
    uint128 accountId;
    int128 sizeDelta;
    uint128 settlementStrategyId;
    uint256 acceptablePrice;
    bytes32 trackingCode;
    address referrer;
  }

  struct Data {
    uint256 commitmentTime;
    OrderCommitmentRequest request;
  }
  /**
   * @notice Commit an async order via this function
   * @param commitment Order commitment data (see AsyncOrder.OrderCommitmentRequest struct).
   * @return retOrder order details (see AsyncOrder.Data struct).
   * @return fees order fees (protocol + settler)
   */
  function commitOrder(OrderCommitmentRequest memory commitment) external returns (Data memory retOrder, uint256 fees);

  /**
   * @notice Simulates what the order fee would be for the given market with the specified size.
   * @dev    Note that this does not include the settlement reward fee, which is based on the strategy type used
   * @param marketId id of the market.
   * @param sizeDelta size of position.
   * @return orderFees incurred fees.
   * @return fillPrice price at which the order would be filled.
   */
  function computeOrderFees(
    uint128 marketId,
    int128 sizeDelta
  ) external view returns (uint256 orderFees, uint256 fillPrice);

  /**
   * @notice Get async order claim details
   * @param accountId id of the account.
   * @return order async order claim details (see AsyncOrder.Data struct).
   */
  function getOrder(uint128 accountId) external view returns (Data memory order);
}
