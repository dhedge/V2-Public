You can use this contract for any price.


# Functions:
- [`constructor(uint80 _roundId, int256 _answer, uint256 _startedAt, uint256 _updatedAt, uint80 _answeredInRound)`](#HackerPriceAggregator-constructor-uint80-int256-uint256-uint256-uint80-)
- [`latestRoundData()`](#HackerPriceAggregator-latestRoundData--)
- [`latestRound()`](#HackerPriceAggregator-latestRound--)
- [`decimals()`](#HackerPriceAggregator-decimals--)



# Function `constructor(uint80 _roundId, int256 _answer, uint256 _startedAt, uint256 _updatedAt, uint80 _answeredInRound)` {#HackerPriceAggregator-constructor-uint80-int256-uint256-uint256-uint80-}
No description




# Function `latestRoundData() → uint80, int256, uint256, uint256, uint80` {#HackerPriceAggregator-latestRoundData--}
Get the latest round data. Should be the same format as chainlink aggregator.



## Return Values:
- roundId The round ID.

- answer The price - the latest round data of USD (price decimal: 8)

- startedAt Timestamp of when the round started.

- updatedAt Timestamp of when the round was updated.

- answeredInRound The round ID of the round in which the answer was computed.


# Function `latestRound() → uint256` {#HackerPriceAggregator-latestRound--}
No description




# Function `decimals() → uint8` {#HackerPriceAggregator-decimals--}
No description




