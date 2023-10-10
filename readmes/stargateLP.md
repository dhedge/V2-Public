# Stargate LP

Liquidity positions on Stargate to facilitate cross-chain transactions for external users.
These are single asset LPs such as USDC, DAI, etc.

The LPs can be staked to earn $STG rewards.

## Resources

Stargate repository for reference:
https://github.com/stargate-protocol/stargate

## Example Transactions

Example transactions:
- [Add liquidity](https://polygonscan.com/tx/0xe62673e827d0929c734894870deb9f6f5c02141ad9110b2a218c0416333107f0)
- [Stake](https://polygonscan.com/tx/0x939bb22582edf3410049a9b1f9d90943e5cb992dd7ac22082db34f3e1893c646)
- [Unstake](https://polygonscan.com/tx/0xd8ab56fac3358986266763a5bebd4fbe68bb5f1d8b9bb83cb0ff9c23a13bc17d)
- [Withdraw](https://polygonscan.com/tx/0x4bf3ff9b0f5be669dbd6002d19c6c3f5fcbba0156f5e86ec3812d6763893031f)

# Contract Guards

## AssetGuard - StargateLPAssetGuard

Each LP type is configured as an asset. This asset is assetType 16.
The StargateLPAssetGuard can be shared by all the Stargate LPs.

`getBalance()` Calculates the value by combining the LP amount in the pool and the staked amount. The amount is converted to the equivalent underlying amount.
Eg. a S*USDC LP token is converted to USDC underlying amount. The oracle for this asset would be USDC.

`withdrawProcessing()` Investors are able to take their portion of any LP. We first withdraw any staked portion before withdrawing to the user.

## ContractGuard - StargateRouterContractGuard

Currently supports:

- addLiquidity
- instantRedeemLocal

These functions are used for minting and withdrawing liquidity.

## ContractGuard - StargateLpStakingContractGuard

Currently supports:

- deposit
- withdraw
- emergencyWithdraw

These functions are used for staking and unstaking the LP tokens to earn rewards.
