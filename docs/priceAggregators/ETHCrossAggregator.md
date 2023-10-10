Convert ETH denominated oracle to USD denominated oracle


# Functions:
- [`constructor(address _token, contract IAggregatorV3Interface _tokenEthAggregator, contract IAggregatorV3Interface _ethUsdAggregator)`](#ETHCrossAggregator-constructor-address-contract-IAggregatorV3Interface-contract-IAggregatorV3Interface-)
- [`decimals()`](#ETHCrossAggregator-decimals--)
- [`latestRoundData()`](#ETHCrossAggregator-latestRoundData--)



# Function `constructor(address _token, contract IAggregatorV3Interface _tokenEthAggregator, contract IAggregatorV3Interface _ethUsdAggregator)` {#ETHCrossAggregator-constructor-address-contract-IAggregatorV3Interface-contract-IAggregatorV3Interface-}
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


