# Velodrome

Velodrome is an AMM based on Solidly (and it on UniV2) but with the addition of stable pools and staking gauges (for rewards). It's pools also allow them to be used as a no-upkeep, flash loan-proof, 30-minute time-weighted average price (TWAP) with direct quoting support to interface with this we have the `VelodromeTWAPAggregator`.

https://github.com/velodrome-finance/contracts/blob/master/contracts/Pair.sol#L241

For Velodrome we only currently support LP'ing with Staking via the related Gauge. We don't currently support Swaps via Velodrome.


# AssetGuard - VelodromeLPAssetGuard

For each Supported Velodrome LP, we, by default we also support its related gauge. The VelodromeLpAssetGuard automatically includes any staked LP tokens, rewards and fees into the aggregate value of the LP Asset. Note this is different to how we support Balancer V2 Gauges, with Balancer V2 Gauges are treated as separate assets, distinct from the LP asset.

One thing to note is the way the AssetGuard calculates the balance, it calculates the cumulative lp + gauge LP token balance and then calculates the rewardsValue and then converts that rewards Value back into a balance of LP tokens. The VelodromeVariableLPAggregator or VelodromeStableLPAggregator then convert that balance back to USD.


# Contract Guards - VelodromeRouterGuard, VelodromeGaugeContractGuard

Unfortunately (and similarly to Balancer), each Staking Gauge is a separate contract which means for each Gauge we need to configure a Contract Guard in Governance. This is in addition to configuring a Contract Guard for the Velodrome Router which enables us to add and remove liquidity for any pair from a central location.

