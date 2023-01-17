You can use this contract for any price.


# Functions:
- [`constructor(int256 _price)`](#FixedPriceAggregator-constructor-int256-)
- [`latestRoundData()`](#FixedPriceAggregator-latestRoundData--)
- [`decimals()`](#FixedPriceAggregator-decimals--)



# Function `constructor(int256 _price)` {#FixedPriceAggregator-constructor-int256-}
No description




# Function `latestRoundData() → uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound` {#FixedPriceAggregator-latestRoundData--}
Get the latest round data. Should be the same format as chainlink aggregator.



## Return Values:
- roundId The round ID.

- answer The price - the latest round data of USD (price decimal: 8)

- startedAt Timestamp of when the round started.

- updatedAt Timestamp of when the round was updated.

- answeredInRound The round ID of the round in which the answer was computed.


# Function `decimals() → uint8` {#FixedPriceAggregator-decimals--}
No description




