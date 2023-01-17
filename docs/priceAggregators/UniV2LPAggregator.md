You can use this contract for lp token pricing oracle.


# Functions:
- [`constructor(address _pair, address _factory)`](#UniV2LPAggregator-constructor-address-address-)
- [`decimals()`](#UniV2LPAggregator-decimals--)
- [`latestRoundData()`](#UniV2LPAggregator-latestRoundData--)



# Function `constructor(address _pair, address _factory)` {#UniV2LPAggregator-constructor-address-address-}
No description




# Function `decimals() → uint8` {#UniV2LPAggregator-decimals--}
No description




# Function `latestRoundData() → uint80, int256, uint256, uint256, uint80` {#UniV2LPAggregator-latestRoundData--}
Get the latest round data. Should be the same format as chainlink aggregator.



## Return Values:
- roundId The round ID.

- answer The price - the latest round data of a given uni-v2 lp token (price decimal: 8)

- startedAt Timestamp of when the round started.

- updatedAt Timestamp of when the round was updated.

- answeredInRound The round ID of the round in which the answer was computed.




