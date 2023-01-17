You can use this contract for MaticX token pricing oracle.


# Functions:
- [`constructor(address _matic, address _maticX, address _maticXPool, address _factory)`](#MaticXPriceAggregator-constructor-address-address-address-address-)
- [`decimals()`](#MaticXPriceAggregator-decimals--)
- [`latestRoundData()`](#MaticXPriceAggregator-latestRoundData--)



# Function `constructor(address _matic, address _maticX, address _maticXPool, address _factory)` {#MaticXPriceAggregator-constructor-address-address-address-address-}
No description




# Function `decimals() → uint8` {#MaticXPriceAggregator-decimals--}
No description




# Function `latestRoundData() → uint80, int256, uint256, uint256, uint80` {#MaticXPriceAggregator-latestRoundData--}
Get the latest round data. Should be the same format as chainlink aggregator.



## Return Values:
- roundId The round ID.

- answer The price - the latest round data of matic token (price decimal: 8)

- startedAt Timestamp of when the round started.

- updatedAt Timestamp of when the round was updated.

- answeredInRound The round ID of the round in which the answer was computed.




