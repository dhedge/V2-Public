You can use this contract for dQUICK token pricing oracle.


# Functions:
- [`constructor(address _dQUICK, address _quick, address _factory)`](#DQUICKPriceAggregator-constructor-address-address-address-)
- [`decimals()`](#DQUICKPriceAggregator-decimals--)
- [`latestRoundData()`](#DQUICKPriceAggregator-latestRoundData--)



# Function `constructor(address _dQUICK, address _quick, address _factory)` {#DQUICKPriceAggregator-constructor-address-address-address-}
No description




# Function `decimals() → uint8` {#DQUICKPriceAggregator-decimals--}
No description




# Function `latestRoundData() → uint80, int256, uint256, uint256, uint80` {#DQUICKPriceAggregator-latestRoundData--}
Get the latest round data. Should be the same format as chainlink aggregator.



## Return Values:
- roundId The round ID.

- answer The price - the latest round data of dQUICk token (price decimal: 8)

- startedAt Timestamp of when the round started.

- updatedAt Timestamp of when the round was updated.

- answeredInRound The round ID of the round in which the answer was computed.




