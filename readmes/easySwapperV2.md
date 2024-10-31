# EasySwapperV2 draft contract specification

The following features were identified, which EasySwapper solved for dHEDGE protocol:

1. Single asset withdrawal (unrolling complex assets and swapping everything to single asset)
2. Native token deposit
3. Lowered lockup deposit for specific (high volatility) vaults
4. Intermediary contract to use as a dHEDGE manager, when buying/selling other dHEDGE vaults within vault

These four features have been pretty stable throughout the years and EasySwapper's use cases were providing real value for the protocol. With this in mind, EasySwapperV2 has been designed.

## Single Asset Withdrawal

Onchain swaps appeared to be major drawback in EasySwapper design. With that said, no onchain swaps should happen on EasySwapperV2. Onchain swaps require significant maintenance costs, while unrolling onchain has not been too troublesome. Verdict: unrolling onchain can be preserved in EasySwapperV2.

The problem with SAW is that in order to use swap data from APIs, the exact amount to be provided must be known to obtain transaction data, which is unknown before assets are unrolled. Solution: make SAW through EasySwapperV2 a two-step process (two separate transactions). The first step is to receive vault tokens, execute the withdrawal, unroll the underlying assets, create so-called `WithdrawalVault` tied up to a specific depositor and put all the funds in there. After the first step is completed, client code can read which ERC20 tokens and how many of each of them are required to be swapped out, and then call the swap API to obtain swap data for each of the tokens. During the second step, the swap data is passed to the second transaction, along with the minimum amount out (slippage protection). This function performs the swaps inside the contract, and if the slippage condition is satisfied, transfers the single asset to the depositor. If depositor is not willing to perform SAW, they can withdraw all the underlying ERC20s received after unrolling from their WithdrawalVault at any time.

## Native Token Deposit

The feature has been very widely adopted in between protocol users, so keeping it in EasySwapperV2 is a must. A few native deposit functions were added, each for separate use case which can be identified from natspec comments.

## Lowered Lockup Deposit

Similar to native token deposit, lowered lockup deposit must be possible in V2 as leverage vaults make up a very huge chunk of protocol's TVL. The feature is tightly coupled with `PoolLogic` (unfortunately), so implementation in V2 was almost completely replicated from EasySwapper. This was made for the sake of not changing core protocol contracts (to which `PoolLogic` belongs).

## Intermediary contract

While `zapDepositWithCustomCooldown` and `depositWithCustomCooldown` can be whitelisted in a contract guard for EasySwapperV2 and used by managers to buy dHEDGE vaults within their dHEDGE vaults with lower lockup similar to V1 version, selling vaults within vaults becomes a bit more sophisticated. Non-atomic withdrawals can not be used when selling something within vault, as we don't want funds to leave the vault and change its token price. However, it's possible to workaround two-step withdrawals from EasySwapperV2 in the following way:

- Add EasySwapperV2 proxy contract address as an asset to `AssetHandler` with its own asset type.
- When making a withdrawal through whitelisted in a contract guard for EasySwapperV2 `initWithdrawal` function, make sure EasySwapperV2 is enabled as an asset in the vault.
- In its own unique asset guard for EasySwapperV2, get `WithdrawalVault` which belongs to a speficic dHEDGE vault, by calling `withdrawalContracts(dHedgeVaultAddress)`. if it exists, read all ERC20 token balances from it and aggregate their value in `getBalance` function.
- `withdrawProcessing` can transfer the portion of each ERC20 from `WithdrawalVault` to the withdrawer.

The above steps will guarantee that once manager calls `initWithdrawal` and underlying tokens will be placed at `WithdrawalVault`, manager's vault won't lose any value and will keep accounting them. If/once manager decides to `completeWithdrawal` either to single or to multiple tokens, contract guard should make sure all destination tokens are enabled in the vault. Also, seems like some bad slippage protection from trades if withdrawing to single token should be added.
