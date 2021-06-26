## `SushiLPAggregator`

You can use this contract for lp token pricing oracle.


This should have `latestRoundData` function as chainlink pricing oracle.


### `constructor(address _pair, address _aggregator0, address _aggregator1)` (public)





### `latestRoundData() → uint80, int256, uint256, uint256, uint80` (external)



Get the latest round data. Should be the same format as chainlink aggregator.


### `_getTokenPrices() → uint256, uint256, uint256` (internal)





### `_getTokenPrice(address aggregator) → int256 answer, uint256 updatedAt` (internal)






