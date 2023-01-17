// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "./IAddressResolver.sol";

interface IFuturesMarket {
  function positions(address account)
    external
    view
    returns (
      uint64 id,
      uint64 fundingIndex,
      uint128 margin,
      uint128 lastPrice,
      int128 size
    );

  function resolver() external view returns (IAddressResolver);

  function transferMargin(int256 marginDelta) external;

  function modifyPositionWithTracking(int256 sizeDelta, bytes32 trackingCode) external;

  function submitNextPriceOrderWithTracking(int256 sizeDelta, bytes32 trackingCode) external;

  function modifyPosition(int256 sizeDelta) external;

  function withdrawAllMargin() external;

  function closePosition() external;

  function closePositionWithTracking(bytes32 trackingCode) external;

  function remainingMargin(address account) external view returns (uint256 marginRemaining, bool invalid);

  function orderFee(int256 sizeDelta) external view returns (uint256 fee, bool invalid);

  function canLiquidate(address account) external view returns (bool);

  function liquidatePosition(address account) external;
}
