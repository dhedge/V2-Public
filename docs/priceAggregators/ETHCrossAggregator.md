Convert ETH denominated oracles to to USD denominated oracle


# Functions:
- [`constructor(address _token, address _tokenEthAggregator, address _ethUsdAggregator)`](#ETHCrossAggregator-constructor-address-address-address-)
- [`decimals()`](#ETHCrossAggregator-decimals--)
- [`latestRoundData()`](#ETHCrossAggregator-latestRoundData--)



# Function `constructor(address _token, address _tokenEthAggregator, address _ethUsdAggregator)` {#ETHCrossAggregator-constructor-address-address-address-}
No description




# Function `decimals() → uint8` {#ETHCrossAggregator-decimals--}
No description




# Function `latestRoundData() → uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound` {#ETHCrossAggregator-latestRoundData--}
Get the latest round data. Should be the same format as chainlink aggregator.



## Return Values:
- roundId The round ID.

- answer The price - the latest round data of USD (price decimal: 8)

- startedAt Timestamp of when the round started.

- updatedAt Timestamp of when the round was updated.

- answeredInRound The round ID of the round in which the answer was computed.


