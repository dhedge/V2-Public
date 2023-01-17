You can use this contract for lp token pricing oracle.


# Functions:
- [`constructor(address _factory, contract IBalancerPool _pool)`](#BalancerStablePoolAggregator-constructor-address-contract-IBalancerPool-)
- [`decimals()`](#BalancerStablePoolAggregator-decimals--)
- [`latestRoundData()`](#BalancerStablePoolAggregator-latestRoundData--)



# Function `constructor(address _factory, contract IBalancerPool _pool)` {#BalancerStablePoolAggregator-constructor-address-contract-IBalancerPool-}
No description




# Function `decimals() → uint8` {#BalancerStablePoolAggregator-decimals--}
No description




# Function `latestRoundData() → uint80, int256, uint256, uint256, uint80` {#BalancerStablePoolAggregator-latestRoundData--}
Get the latest round data. Should be the same format as chainlink aggregator.



## Return Values:
- roundId The round ID.

- answer The price - the latest round data of a given balancer-v2 lp token (price decimal: 8)

- startedAt Timestamp of when the round started.

- updatedAt Timestamp of when the round was updated.

- answeredInRound The round ID of the round in which the answer was computed.








