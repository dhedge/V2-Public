This should have `latestRoundData` function as chainlink pricing oracle.

# Functions:
- [`constructor(address _pair, address _aggregator0, address _aggregator1)`](#SushiLPAggregator-constructor-address-address-address-)
- [`latestRoundData()`](#SushiLPAggregator-latestRoundData--)


# Function `constructor(address _pair, address _aggregator0, address _aggregator1)` {#SushiLPAggregator-constructor-address-address-address-}
No description
# Function `latestRoundData() → uint80, int256, uint256, uint256, uint80` {#SushiLPAggregator-latestRoundData--}
Get the latest round data. Should be the same format as chainlink aggregator.

## Return Values:
- Returns the latest round data of a given sushi lp token (price decimal: 8)

