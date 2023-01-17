# Introduction
Arrakis Finance allows for Uniswap V3 LP liquidity mining. They’re a Gelato spinoff and use Gelato’s Uni v3 LP contract.
To start with, could enable multiple pools including USDC-miMATIC LP (which we can use for dUSD farming).

## Contracts
- [ArrakisV1RouterStaking](https://polygonscan.com/address/0xbc91a120ccd8f80b819eaf32f0996dac3fa76a6c#code)
Creates Uni v3 LP token and adds it to a liquidity gauge. It mints an LP staked token back to the user.

- [Rewards Harvester](https://polygonscan.com/address/0x5e65a272fb0d594c7447f05928011c4f7f53c808)
Currently gives MATIC rewards.

## Example transactions
- [`addLiquidityAndStake`](https://polygonscan.com/tx/0x23fdede6386956973f83c7042371c6f55b12a7a3b31bd7b71358a6c096263dd0)
Note that they don’t use the NonfungiblePositionManager, but mint directly in the pool. So there is no NFT for the position.
- [`claim_rewards`](https://polygonscan.com/tx/0xf55415f8b483235295c2d09702c0284be06d1da36d0c01ad4d6c8d52bb765503)
- [`removeLiquidityAndUnstake`](https://polygonscan.com/tx/0xef3d397333d85c7a7b0e3dc353d31937bfa12591cc81b7abf81da553423e08a0)
Remove 50% of staked value

# Implementation

## Contract Guards

### ArrakisV1RouterStakingGuard

#### `addLiquidityAndStake`
Inputs:
address gauge:  This is the staked token harvester eg USDC-miMATIC harvester (implementation)
uint256 amount0Max: Token 0 of LP maximum
uint256 amount1Max: Token 1 of LP maximum
uint256 amount0Min: Token 0 of LP minimum
uint256 amount1Min: Token 1 of LP minimum
address receiver: The receiver of the LP

Guard implementation:
- Gauge input: Gauge asset should be supported by the pool logic contract - asset type = `9`
- Gauge input: Both token0 and token1 should be supported by the pool logic contract. (Ensure that the LP underlying tokens (eg USDC & miMATIC) are supported by the pool. Get the token0/1 addresses by calling: harvester.staking_token.token0/token1)
- Ensure the reward tokens are supported by the pool logic.
- Ensure the receiver is the dHEDGE pool
- Can only have a maximum of 2 liquidity positions / gauges at any one time (will need to check positions for all the whitelisted gauges)

#### `removeLiquidityAndUnstake`
Inputs:
address gauge:  This is the staked token harvester eg USDC-miMATIC harvester (implementation)
uint256 burnAmount: LP amount to burn
uint256 amount0Min: Token 0 of LP minimum
uint256 amount1Min: Token 1 of LP minimum
address receiver: The receiver of the LP

Guard implementation:
- Gauge input: Gauge asset should be supported by the pool logic contract - asset type = `9`
- Gauge input: Both token0 and token1 should be supported by the pool logic contract. (Ensure that the LP underlying tokens (eg USDC & miMATIC) are supported by the pool. Get the token0/1 addresses by calling: harvester.staking_token.token0/token1)
- Ensure the reward tokens are supported by the pool logic.
- Ensure the receiver is the dHEDGE pool

### `ArrakisLiquidityGaugeV4ContractGuard`

- `claim_rewards()`
- `claim_rewards(address user)`
- `claim_rewards(address user,address receiver)`

Guard implementation:
- Ensure the reward tokens are supported by the pool logic.
- Ensure both user/receiver is the dHEDGE pool

## Asset Guard

### `ArrakisLiquidityGaugeV4AssetGuard`
Asset guard for the staked Arrakis Uni v3 vault tokens (new Asset Type)
The dHEDGE pool will receive the staked LP token.

- `getBalance`
The balance will be similar to the UniswapV3AssetGuard, where we would calculate the value of the position in $ terms.

First of all, calculate the underlying USD amount of uniswap v3 lp position.
`gauge.staking_token()` has `IArrakisVaultV1` interface and there you can find `getUnderlyingBalances()` function which calculates the position amount0/amount1 based on the current price tick.

After that, need to sum up the reward tokens in USD.
FYI, each gauge can have multiple reward tokens.
We use `gauge.reward_count()`, `gauge.reward_tokens()`, `gauge.claimable_reward()` to calculate the reward token amount in USD.

- `withdrawProcessing`

First of all, calculate the burn amount based on the portion to withdraw.
Then, approve burn amount of gauge asset for arrakis v1 router staking contract.
After that, call removeLiquidityAndUnstake function and specify receiver as user address.
* removeLiquidityAndUnstake claims an unclaimed rewards to the msg.sender (in this case the pool)
* The removed liquidity is sent directly the withdrawer.

### Asset Aggregator
Use the USDPriceAggregator (fixed $1 value)
