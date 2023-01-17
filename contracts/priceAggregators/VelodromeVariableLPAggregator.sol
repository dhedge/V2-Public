// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "./UniV2LPAggregator.sol";

/**
 * @title Velodrome Variable LP aggregator. For dHEDGE LP Price Feeds.
 * @notice You can use this contract for Velodrome lp token pricing oracle.
 * @dev This should have `latestRoundData` function as chainlink pricing oracle.
 */
contract VelodromeVariableLPAggregator is UniV2LPAggregator {
  // solhint-disable-next-line no-empty-blocks
  constructor(address _pair, address _factory) UniV2LPAggregator(_pair, _factory) {}
}
