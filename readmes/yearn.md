# Yearn Vault

Field of study:
- https://yearn.finance/vaults/10/0xbC61B71562b01a3a4808D3B9291A3Bf743AB3361
- [Velodrome v2 LUSD-WETH Factory yVault](https://optimistic.etherscan.io/address/0xbc61b71562b01a3a4808d3b9291a3bf743ab3361#writeContract)

## Example transactions

1. https://optimistic.etherscan.io/tx/0x886fb869be497cb4333df69a4f033084d703eee7f4f7aec44a757b1b042fae91 `Approve` [WidoTokenManager](https://optimistic.etherscan.io/address/0xc1ae663b4b4d211b4f865dc36a0db36ffcf71528#code) to spend deposit asset (optional, see point 2)
2. https://optimistic.etherscan.io/tx/0x1648badd3cf5b78bedfef930d8d78a60ddde6e9b6cf7f3a53b1e1ddef2b0b2fd `ExecuteOrder` (deposit) on [WidoRouter](https://optimistic.etherscan.io/address/0x9b2ed3c2a92ad366ebf90bbcec31be231320ac26#code) NB: thie is in case we need other than [VolatileV2 AMM - WETH/LUSD](https://optimistic.etherscan.io/address/0x6387765ffa609ab9a1da1b16c455548bfed7cbea) deposit asset, otherwise `deposit` on [Velodrome v2 LUSD-WETH Factory yVault](https://optimistic.etherscan.io/address/0xbc61b71562b01a3a4808d3b9291a3bf743ab3361#writeContract)
3. https://optimistic.etherscan.io/tx/0xd3eaa91dc0eb778ee7199fd27f101aea5037b8613a4cc6e09524b8dc41751cab `Approve` Yearn Vault tokens for [StakingRewards](https://optimistic.etherscan.io/address/0x0e4e9914ecf0f7177ef999774d46218614555159) contract
4. https://optimistic.etherscan.io/tx/0xf093bc575b2cd343b8b9a488911f65e9f0a3e6a5f885f183c7b1fce9f4776c89 `Stake` Yearn Vault tokens to receive OP rewards
5. https://optimistic.etherscan.io/tx/0xf94d5854f6aa907f9a330ca541f557cb4fb2efe12e48cef5c58600c62af27d27 `getReward` Claim rewards in form of [OP yVault](https://optimistic.etherscan.io/address/0x7d2382b1f8af621229d33464340541db362b4907) tokens 
6. https://optimistic.etherscan.io/tx/0x9da13e9a90f56b7fd9edd52695278b41f42e98d140a5453d0ebf3004ab6c6c5e `Withdraw` from OP yVault, receive OP tokens
7. `exit` or `withdraw` from [StakingRewards](https://optimistic.etherscan.io/address/0x0e4e9914ecf0f7177ef999774d46218614555159#writeContract) contract to get back Yearn Vault tokens
8. `Withdraw` from [Velodrome v2 LUSD-WETH Factory yVault](https://optimistic.etherscan.io/address/0xbc61b71562b01a3a4808d3b9291a3bf743ab3361#writeContract) and receive [VolatileV2 AMM - WETH/LUSD](https://optimistic.etherscan.io/address/0x6387765ffa609ab9a1da1b16c455548bfed7cbea) tokens

## Accounting

Balance of LUSD-WETH yVault tokens in dHEDGE Pool + balance of LUSD-WETH yVault tokens staked by dHEDGE Pool in StakingRewards contract + balance of OP Tokens eligible for claiming on behalf of dHEDGE Pool. `VelodromeVariableLPAggregator` for the underlying WETH-LUSD Velodrome V2 Pair and [`pricePerShare`](https://optimistic.etherscan.io/token/0xbc61b71562b01a3a4808d3b9291a3bf743ab3361#readContract) of the Yearn Vault.

## Withdrawing

- Claim a portion of OP rewards
- Withdraw from OP yVault, get OP tokens
- Unstake a portion of yearn vault tokens from staking rewards contract
- Withdraw received tokens from LUSD-WETH yVault, get [VolatileV2 AMM - WETH/LUSD](https://optimistic.etherscan.io/address/0x6387765ffa609ab9a1da1b16c455548bfed7cbea) tokens

## Guards

- New asset type for yearn vault.
- `YearnVaultVelodromeAssetGuard` for this type of asset
- Price aggregator for this type of asset
- `ClosedContractGuard` for the [WidoTokenManager](https://optimistic.etherscan.io/address/0xc1ae663b4b4d211b4f865dc36a0db36ffcf71528#code) (optional)
- Contract guard for [WidoRouter](https://optimistic.etherscan.io/address/0x9b2ed3c2a92ad366ebf90bbcec31be231320ac26#code) (optional)
- Contract guard for [StakingRewards](https://optimistic.etherscan.io/address/0x0e4e9914ecf0f7177ef999774d46218614555159)
- Contract guard for [OP yVault](https://optimistic.etherscan.io/address/0x7d2382b1f8af621229d33464340541db362b4907)
- Contract guard [Velodrome v2 LUSD-WETH Factory yVault](https://optimistic.etherscan.io/address/0xbc61b71562b01a3a4808d3b9291a3bf743ab3361#writeContract)
