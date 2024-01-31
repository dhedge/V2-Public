// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "./UniV2LPAggregator.sol";

contract RamsesVariableLPAggregator is UniV2LPAggregator {
  // solhint-disable-next-line no-empty-blocks
  constructor(address _pair, address _factory) UniV2LPAggregator(_pair, _factory) {}
}
