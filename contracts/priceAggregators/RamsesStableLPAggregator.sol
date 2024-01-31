// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "./VelodromeStableLPAggregator.sol";

contract RamsesStableLPAggregator is VelodromeStableLPAggregator {
  // solhint-disable-next-line no-empty-blocks
  constructor(address _pair, address _factory) VelodromeStableLPAggregator(_pair, _factory) {}
}
