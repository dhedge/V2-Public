// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "./IAddressResolver.sol";

interface IPerpsV2Market {
  /* ========== TYPES ========== */

  enum OrderType {
    Atomic,
    Delayed,
    Offchain
  }

  enum Status {
    Ok,
    InvalidPrice,
    InvalidOrderType,
    PriceOutOfBounds,
    CanLiquidate,
    CannotLiquidate,
    MaxMarketSizeExceeded,
    MaxLeverageExceeded,
    InsufficientMargin,
    NotPermitted,
    NilOrder,
    NoPositionOpen,
    PriceTooVolatile,
    PriceImpactToleranceExceeded
  }

  // If margin/size are positive, the position is long; if negative then it is short.
  struct Position {
    uint64 id;
    uint64 lastFundingIndex;
    uint128 margin;
    uint128 lastPrice;
    int128 size;
  }

  // Delayed order storage
  struct DelayedOrder {
    bool isOffchain; // flag indicating the delayed order is offchain
    int128 sizeDelta; // difference in position to pass to modifyPosition
    uint128 desiredFillPrice; // minimum price to be used on fillPrice at execution
    uint128 targetRoundId; // price oracle roundId using which price this order needs to executed
    uint128 commitDeposit; // the commitDeposit paid upon submitting that needs to be refunded if order succeeds
    uint128 keeperDeposit; // the keeperDeposit paid upon submitting that needs to be paid / refunded on tx confirmation
    uint256 executableAtTime; // The timestamp at which this order is executable at
    uint256 intentionTime; // The block timestamp of submission
    bytes32 trackingCode; // tracking code to emit on execution for volume source fee sharing
  }

  function postTradeDetails(
    int256 sizeDelta,
    uint256 tradePrice,
    OrderType orderType,
    address sender
  ) external view returns (uint256 margin, int256 size, uint256 price, uint256 liqPrice, uint256 fee, Status status);

  function fillPrice(int256 sizeDelta) external view returns (uint256 price, bool invalid);

  function resolver() external view returns (IAddressResolver);

  function positions(address account) external view returns (Position memory);

  function remainingMargin(address account) external view returns (uint256 marginRemaining, bool invalid);

  function accessibleMargin(address account) external view returns (uint256 marginAccessible, bool invalid);

  function canLiquidate(address account) external view returns (bool);

  function orderFee(int256 sizeDelta, OrderType orderType) external view returns (uint256 fee, bool invalid);

  function liquidatePosition(address account) external;

  function modifyPosition(int256 sizeDelta, uint256 desiredFillPrice) external;

  function modifyPositionWithTracking(int256 sizeDelta, uint256 desiredFillPrice, bytes32 trackingCode) external;

  function transferMargin(int256 marginDelta) external;

  function withdrawAllMargin() external;

  function closePosition(uint256 desiredFillPrice) external;

  function closePositionWithTracking(uint256 desiredFillPrice, bytes32 trackingCode) external;

  function submitOffchainDelayedOrder(int256 sizeDelta, uint256 desiredFillPrice) external;

  function submitOffchainDelayedOrderWithTracking(
    int256 sizeDelta,
    uint256 desiredFillPrice,
    bytes32 trackingCode
  ) external;

  function executeOffchainDelayedOrder(address account, bytes[] calldata priceUpdateData) external payable;

  function cancelOffchainDelayedOrder(address account) external;

  function submitDelayedOrder(int256 sizeDelta, uint256 desiredFillPrice, uint256 desiredTimeDelta) external;

  function submitDelayedOrderWithTracking(
    int256 sizeDelta,
    uint256 desiredFillPrice,
    uint256 desiredTimeDelta,
    bytes32 trackingCode
  ) external;

  function cancelDelayedOrder(address account) external;

  function delayedOrders(address account) external view returns (DelayedOrder memory);
}
