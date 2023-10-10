# Synthetix V3

This document will outline an integration path for Synthetix v3 (still a work in progress).
It will mainly describe the functionality relevant to a dHEDGE integration.

The general flow for a staker is as follows:

- Create an account (NFT)
- Deposit some collateral to the account
- Assign/delegate the collateral to a pool (multiple pool options)
- Create a debt position from that pool (mint snxUSD)

Unlike Synthetix v2, v3 has multiple pools (not just 1). Anyone can create a pool.
Just like v2, these pools can have an associated debt and markets (synths).


## Resources

Most of the information for this integration is contained in the following:

- https://snx-v3-docs.vercel.app/
- https://github.com/Synthetixio/synthetix-v3/tree/main/protocol/synthetix/contracts

## Accounts

Accounts logic is in the [account module](https://github.com/Synthetixio/synthetix-v3/blob/main/protocol/synthetix/contracts/modules/core/AccountModule.sol).

An account is an ERC721 token and is created with the `createAccount` function.
A dHedge pool should firstly create an account associated with the pool.

All positions (ie. collateral and debt) are associated with an account. It's likely that dHedge should track the manager's positions to avoid having to loop through all the possible collateral and pools.

## ContractGuards

### AccountModule

For creating an account for the dHedge pool to interact with Synthetix.
Can support:

- [createAccount](https://github.com/Synthetixio/synthetix-v3/blob/main/protocol/synthetix/contracts/modules/core/AccountModule.sol#L55)

Should ensure that the dHedge pool has only a single account.

### CollateralModule

For depositing collateral. Can support:

- [deposit](https://github.com/Synthetixio/synthetix-v3/blob/main/protocol/synthetix/contracts/modules/core/CollateralModule.sol#L32)
- [withdraw](https://github.com/Synthetixio/synthetix-v3/blob/main/protocol/synthetix/contracts/modules/core/CollateralModule.sol#L62)

### VaultModule

For assigning collateral to a pool. Can support:

- [delegateCollateral](https://github.com/Synthetixio/synthetix-v3/blob/main/protocol/synthetix/contracts/modules/core/VaultModule.sol#L41)

### IssueUSDModule

For minting snxUSD. Can support:

- [mintUsd](https://github.com/Synthetixio/synthetix-v3/blob/main/protocol/synthetix/contracts/modules/core/IssueUSDModule.sol#L38)
- [burnUsd](https://github.com/Synthetixio/synthetix-v3/blob/main/protocol/synthetix/contracts/modules/core/IssueUSDModule.sol#L81)

### MulticallModule

Can support:

- [multicall](https://github.com/Synthetixio/synthetix-v3/blob/main/protocol/synthetix/contracts/modules/core/MulticallModule.sol#L15)

### AtomicOrderModule

For atomic swaps. Can support:

- [buy](https://github.com/Synthetixio/synthetix-v3/blob/main/markets/spot-market/contracts/modules/AtomicOrderModule.sol#L26)
- [sell](https://github.com/Synthetixio/synthetix-v3/blob/main/markets/spot-market/contracts/modules/AtomicOrderModule.sol#L61)

### AsyncOrderModule

For async swaps (lower fees) in 2 steps with a delay.

Can support:

- [commitOrder](https://github.com/Synthetixio/synthetix-v3/blob/main/markets/spot-market/contracts/modules/AsyncOrderModule.sol#L33)
- [settleOrder](https://github.com/Synthetixio/synthetix-v3/blob/main/markets/spot-market/contracts/modules/AsyncOrderModule.sol#L151)

### RewardManagerModule

For claiming rewards. The reward amount is dependant on the [amount of debt](https://github.com/Synthetixio/synthetix-v3/blob/main/protocol/synthetix/contracts/storage/Vault.sol#L117) issued for the account.
Can support:

- [claimRewards]

## AssetGuard - AccountModule

To get an account's full collateral and debt positions in a gas-efficient way, we should track the following for the pool's account ID:

- used collateral types
- delegated pool ids
By tracking the above, it means that we don't need to loop through all the Synthetix collateral types and pools to get the totals.

Tracks an account's collateral and debt positions using the VaultModule:

- [getPositionCollateral](https://github.com/Synthetixio/synthetix-v3/blob/main/protocol/synthetix/contracts/modules/core/VaultModule.sol#L149)
- [getPositionDebt](https://github.com/Synthetixio/synthetix-v3/blob/main/protocol/synthetix/contracts/modules/core/VaultModule.sol#L190)

The value of all the aggreagate Synthetix positions = `value of all position collateral - value of all position debt`
