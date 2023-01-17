You can use this contract for usd price = $1.


# Functions:
- [`decimals()`](#USDPriceAggregator-decimals--)
- [`latestRoundData()`](#USDPriceAggregator-latestRoundData--)



# Function `decimals() → uint8` {#USDPriceAggregator-decimals--}
No description




# Function `latestRoundData() → uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound` {#USDPriceAggregator-latestRoundData--}
Get the latest round data. Should be the same format as chainlink aggregator.



## Return Values:
- roundId The round ID.

- answer The price - the latest round data of USD (price decimal: 8)

- startedAt Timestamp of when the round started.

- updatedAt Timestamp of when the round was updated.

- answeredInRound The round ID of the round in which the answer was computed.


