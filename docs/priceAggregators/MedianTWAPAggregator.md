Convert ETH denominated oracles to to USD denominated oracle


# Functions:
- [`receive()`](#MedianTWAPAggregator-receive--)
- [`fallback()`](#MedianTWAPAggregator-fallback--)
- [`constructor(contract IUniswapV2Pair _pair, address _mainToken, contract IAggregatorV3Interface _pairTokenUsdAggregator, uint256 _updateInterval, uint32 _volatilityTripLimit)`](#MedianTWAPAggregator-constructor-contract-IUniswapV2Pair-address-contract-IAggregatorV3Interface-uint256-uint32-)
- [`decimals()`](#MedianTWAPAggregator-decimals--)
- [`consult()`](#MedianTWAPAggregator-consult--)
- [`highVolatility(int256 twapA, int256 twapB)`](#MedianTWAPAggregator-highVolatility-int256-int256-)
- [`latestRoundData()`](#MedianTWAPAggregator-latestRoundData--)
- [`pause()`](#MedianTWAPAggregator-pause--)
- [`unpause()`](#MedianTWAPAggregator-unpause--)
- [`setVolatilityTripLimit(uint32 _volatilityTripLimit)`](#MedianTWAPAggregator-setVolatilityTripLimit-uint32-)
- [`setUpdateInterval(uint256 _updateInterval)`](#MedianTWAPAggregator-setUpdateInterval-uint256-)
- [`withdraw(uint256 amount)`](#MedianTWAPAggregator-withdraw-uint256-)
- [`update()`](#MedianTWAPAggregator-update--)
- [`updateWithIncentive()`](#MedianTWAPAggregator-updateWithIncentive--)

# Events:
- [`UpdateIntervalSet(uint256 updateInterval)`](#MedianTWAPAggregator-UpdateIntervalSet-uint256-)
- [`VolatilityTripLimitSet(uint32 volatilityTripLimit)`](#MedianTWAPAggregator-VolatilityTripLimitSet-uint32-)
- [`Withdraw(uint256 withdrawAmount)`](#MedianTWAPAggregator-Withdraw-uint256-)
- [`Updated(address caller)`](#MedianTWAPAggregator-Updated-address-)
- [`UpdatedWithIncentive(address caller, uint256 amount)`](#MedianTWAPAggregator-UpdatedWithIncentive-address-uint256-)


# Function `receive()` {#MedianTWAPAggregator-receive--}
No description




# Function `fallback()` {#MedianTWAPAggregator-fallback--}
No description




# Function `constructor(contract IUniswapV2Pair _pair, address _mainToken, contract IAggregatorV3Interface _pairTokenUsdAggregator, uint256 _updateInterval, uint32 _volatilityTripLimit)` {#MedianTWAPAggregator-constructor-contract-IUniswapV2Pair-address-contract-IAggregatorV3Interface-uint256-uint32-}
No description




# Function `decimals() → uint8` {#MedianTWAPAggregator-decimals--}
No description




# Function `consult() → int256 price` {#MedianTWAPAggregator-consult--}
Gets the main token median TWAP price (priced in pair token)




# Function `highVolatility(int256 twapA, int256 twapB) → bool volatilityHigh` {#MedianTWAPAggregator-highVolatility-int256-int256-}
Checks for high price volatility in the recent TWAPs






# Function `latestRoundData() → uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound` {#MedianTWAPAggregator-latestRoundData--}
Get the latest round data. Should be the same format as chainlink aggregator.



## Return Values:
- roundId The round ID.

- answer The price - the latest round data of USD (price decimal: 8)

- startedAt Timestamp of when the round started.

- updatedAt Timestamp of when the round was updated.

- answeredInRound The round ID of the round in which the answer was computed.


# Function `pause()` {#MedianTWAPAggregator-pause--}
No description




# Function `unpause()` {#MedianTWAPAggregator-unpause--}
No description




# Function `setVolatilityTripLimit(uint32 _volatilityTripLimit)` {#MedianTWAPAggregator-setVolatilityTripLimit-uint32-}
No description




# Function `setUpdateInterval(uint256 _updateInterval)` {#MedianTWAPAggregator-setUpdateInterval-uint256-}
No description




# Function `withdraw(uint256 amount)` {#MedianTWAPAggregator-withdraw-uint256-}
Withdraws any native token deposits to the owner




# Function `update()` {#MedianTWAPAggregator-update--}
Creates a new TWAP (update interval must pass first)




# Function `updateWithIncentive()` {#MedianTWAPAggregator-updateWithIncentive--}
Creates a new TWAP and gives caller a native token reward (update interval must pass first)






