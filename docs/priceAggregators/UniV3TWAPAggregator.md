Convert ETH denominated oracles to to USD denominated oracle


# Functions:
- [`constructor(contract IUniswapV3Pool _pool, address _mainToken, contract IAggregatorV3Interface _pairTokenUsdAggregator, int256 _priceLowerLimit, int256 _priceUpperLimit, uint32 _updateInterval)`](#UniV3TWAPAggregator-constructor-contract-IUniswapV3Pool-address-contract-IAggregatorV3Interface-int256-int256-uint32-)
- [`decimals()`](#UniV3TWAPAggregator-decimals--)
- [`latestRoundData()`](#UniV3TWAPAggregator-latestRoundData--)



# Function `constructor(contract IUniswapV3Pool _pool, address _mainToken, contract IAggregatorV3Interface _pairTokenUsdAggregator, int256 _priceLowerLimit, int256 _priceUpperLimit, uint32 _updateInterval)` {#UniV3TWAPAggregator-constructor-contract-IUniswapV3Pool-address-contract-IAggregatorV3Interface-int256-int256-uint32-}
No description




# Function `decimals() → uint8` {#UniV3TWAPAggregator-decimals--}
No description




# Function `latestRoundData() → uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound` {#UniV3TWAPAggregator-latestRoundData--}
Get the latest round data. Should be the same format as chainlink aggregator.



## Return Values:
- roundId The round ID.

- answer The price - the latest round data of USD (price decimal: 8)

- startedAt Timestamp of when the round started.

- updatedAt Timestamp of when the round was updated.

- answeredInRound The round ID of the round in which the answer was computed.


