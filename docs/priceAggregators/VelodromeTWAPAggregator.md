You can use this contract for token pricing oracle using Velodrome TWAP.


# Functions:
- [`constructor(address _pair, address _mainToken, address _pairToken, contract IAggregatorV3Interface _pairTokenUsdAggregator)`](#VelodromeTWAPAggregator-constructor-address-address-address-contract-IAggregatorV3Interface-)
- [`decimals()`](#VelodromeTWAPAggregator-decimals--)
- [`latestRoundData()`](#VelodromeTWAPAggregator-latestRoundData--)



# Function `constructor(address _pair, address _mainToken, address _pairToken, contract IAggregatorV3Interface _pairTokenUsdAggregator)` {#VelodromeTWAPAggregator-constructor-address-address-address-contract-IAggregatorV3Interface-}
No description




# Function `decimals() → uint8` {#VelodromeTWAPAggregator-decimals--}
No description




# Function `latestRoundData() → uint80, int256, uint256, uint256, uint80` {#VelodromeTWAPAggregator-latestRoundData--}
Get the latest round data. Should be the same format as chainlink aggregator.



## Return Values:
- roundId The round ID.

- answer The price - the latest round data of a given velodrome lp token (price decimal: 8)

- startedAt Timestamp of when the round started.

- updatedAt Timestamp of when the round was updated.

- answeredInRound The round ID of the round in which the answer was computed.


