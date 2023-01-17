Convert Susd priced assets into usd priced assets


# Functions:
- [`constructor(address _susdPriceAggregator, address _tokenPriceAggregator)`](#SynthPriceAggregator-constructor-address-address-)
- [`latestRoundData()`](#SynthPriceAggregator-latestRoundData--)
- [`decimals()`](#SynthPriceAggregator-decimals--)



# Function `constructor(address _susdPriceAggregator, address _tokenPriceAggregator)` {#SynthPriceAggregator-constructor-address-address-}
No description




# Function `latestRoundData() → uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound` {#SynthPriceAggregator-latestRoundData--}
Get the latest round data. Should be the same format as chainlink aggregator.



## Return Values:
- roundId The round ID.

- answer The price - the latest round data of USD (price decimal: 8)

- startedAt Timestamp of when the round started.

- updatedAt Timestamp of when the round was updated.

- answeredInRound The round ID of the round in which the answer was computed.


# Function `decimals() → uint8` {#SynthPriceAggregator-decimals--}
No description




