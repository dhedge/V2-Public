# Sky (MakerDAO) USDS and sUSDS

This document will outline an asset and staking integration for Sky's USDS and sUSDS (staked) assets.

USDS is a US dollar pegged stablecoin. When staking it, the user receives SUSDS which accrues in value vs USDS over time. The user can unstake it at any time and receive their USDS with no fee.

## Asset price oracles

### Base

https://github.com/sparkdotfi/spark-address-registry/blob/master/src/Base.sol

sUSDS / USDS oracle: [0x026a5B6114431d8F3eF2fA0E1B2EDdDccA9c540E](https://basescan.org/address/0x026a5B6114431d8F3eF2fA0E1B2EDdDccA9c540E#readContract)

USDS / USD Chanlink oracle: [0x2330aaE3bca5F05169d5f4597964D44522F62930](https://basescan.org/address/0x2330aaE3bca5F05169d5f4597964D44522F62930#readContract)

https://data.chain.link/feeds/base/base/usds-usd

### Arbitrum

https://github.com/sparkdotfi/spark-address-registry/blob/master/src/Arbitrum.sol

sUSDS / USDS oracle: [0x84AB0c8C158A1cD0d215BE2746cCa668B79cc287](https://arbiscan.io/address/0x84AB0c8C158A1cD0d215BE2746cCa668B79cc287#readContract)

USDS / USD Chanlink oracle: [0x37833E5b3fbbEd4D613a3e0C354eF91A42B81eeB](https://arbiscan.io/address/0x37833E5b3fbbEd4D613a3e0C354eF91A42B81eeB)

## Contract Guards

### PSM3

On L2s, instead of staking USDS, the user can simply swap between USDC, USDS and sUSDS.

https://docs.spark.fi/dev/savings/spark-psm

The Spark PSM extends the Sky PSM liquidity on Ethereum mainnet to other chains such as Base and Arbitrum. It allows swaps between USDS, sUSDS, and USDC with no slippage or fees beyond gas, making it the top liquidity source for these pairs in DeFi. This enables holders of USDC on supported networks to easily acquire sUSDS to earn yield, at no cost beyond gas.

PSM addresses on Base and Arbitrum:

https://basescan.org/address/0x1601843c5E9bC251A3272907010AFa41Fa18347E#code

https://arbiscan.io/address/0x2B05F8e1cACC6974fD79A673a341Fe1f58d27266

- [swapExactIn](https://github.com/sparkdotfi/spark-psm/blob/master/src/PSM3.sol#L110)

- [swapExactOut](https://github.com/sparkdotfi/spark-psm/blob/master/src/PSM3.sol#L133)

Ensure the `assetOut` is supported by the vault and accumulate slippage.
The `receiver` address should be the vault address.

EasySwapper should support it also ideally.
