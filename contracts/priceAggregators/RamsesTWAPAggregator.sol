// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "./VelodromeTWAPAggregator.sol";

contract RamsesTWAPAggregator is VelodromeTWAPAggregator {
  constructor(
    address _pair,
    address _mainToken,
    address _pairToken,
    IAggregatorV3Interface _pairTokenUsdAggregator
  )
    VelodromeTWAPAggregator(_pair, _mainToken, _pairToken, _pairTokenUsdAggregator) // solhint-disable-next-line no-empty-blocks
  {}
}
