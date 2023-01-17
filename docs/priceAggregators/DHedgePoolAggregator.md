

# Functions:
- [`constructor(address _poolLogic)`](#DHedgePoolAggregator-constructor-address-)
- [`decimals()`](#DHedgePoolAggregator-decimals--)
- [`latestRoundData()`](#DHedgePoolAggregator-latestRoundData--)



# Function `constructor(address _poolLogic)` {#DHedgePoolAggregator-constructor-address-}
No description




# Function `decimals() → uint8` {#DHedgePoolAggregator-decimals--}
No description




# Function `latestRoundData() → uint80, int256, uint256, uint256, uint80` {#DHedgePoolAggregator-latestRoundData--}
Get the latest round data. Should be the same format as chainlink aggregator.



## Return Values:
- roundId The round ID.

- answer The price - the latest round data of a given DHEDGE pool (price decimal: 8)

- startedAt Timestamp of when the round started.

- updatedAt Timestamp of when the round was updated.

- answeredInRound The round ID of the round in which the answer was computed.


