# Value Manipulation Check

## Overview

The Value Manipulation Check is a security mechanism that prevents atomic vault value manipulation attacks in dHEDGE vaults. This is critical for protecting lending markets that use dHEDGE vault tokens as collateral.

## Problem Statement

When dHEDGE vaults are used as collateral in lending markets, a critical attack vector becomes possible:

### Attack Scenario: Flashloan Share Manipulation

1. **Flashloan vault shares** from lending market
2. **Redeem shares** → receive underlying assets at the current (higher) ratio
3. **Trigger liquidation** on the vault, lowering its asset/share ratio
4. **Deposit assets** back into the vault → receive more shares than originally borrowed
5. **Repay the flashloan**, keeping the surplus shares as profit

This attack exploits the ability to manipulate the vault's asset-to-share ratio within a single atomic transaction, allowing the attacker to profit from the price difference between withdrawal and deposit.

Additionally, the check prevents mixing different operation types (deposit, withdraw, execTransaction) within a single transaction, blocking attacks that combine operations to manipulate vault state.

## Solution

The implemented solution provides two layers of protection:

### 1. Fund Value Consistency Check

Prevents unexpected vault fund value changes within a single transaction by:

1. **First Vault Action**: When a deposit or withdrawal occurs, the expected fund value after the operation is stored in transient storage
2. **Subsequent Vault Actions**: On any additional deposit/withdrawal in the same transaction, the current fund value is compared to the stored expected value
3. **Value Change Detection**: If the values differ beyond tolerance (0.001 or ~$0.001), the transaction is reverted with `ValueManipulationDetected` error

This prevents the attack scenario above because the attacker cannot withdraw and then deposit within the same transaction or if the vault's fund value has changed unexpectedly due to external manipulation (e.g., donations).

### 2. Operation Type Enforcement

Prevents mixing different operation types within a single transaction by:

1. **First Operation**: The first operation (deposit, withdraw, or execTransaction) locks the operation type in transient storage
2. **Subsequent Operations**: Any additional operation in the same transaction must match the locked type
3. **Type Mismatch Detection**: If a different operation type is attempted, the transaction is reverted with `OperationTypeMismatch` error

This blocks attacks that combine deposits with withdrawals, or either with execTransaction, preventing complex multi-step atomic manipulations.

### Why Transient Storage?

[EIP-1153](https://eips.ethereum.org/EIPS/eip-1153) transient storage is perfect for this use case because:

- **Automatic Cleanup**: Storage is automatically cleared at the end of each transaction
- **Gas Efficient**: Cheaper than regular SSTORE/SLOAD for single-transaction state
- **Transaction-Scoped**: Prevents intra-transaction manipulation while allowing normal multi-transaction usage
- **No State Bloat**: Doesn't add to permanent blockchain state

## Architecture

### Contracts

#### ValueManipulationCheck.sol (Solidity 0.8.28)

- Standalone library contract using transient storage
- Provides `checkValueManipulation(address pool, uint256 currentFundValue, uint256 expectedFundValueAfter)` function for value consistency
- Provides `checkOperationType(address pool, OperationType operationType)` function for operation type enforcement
- Uses EIP-1153 TSTORE/TLOAD opcodes for transient storage

#### PoolLogic.sol (Solidity 0.7.6)

- Modified to call `ValueManipulationCheck` during deposits, withdrawals, and execTransactions
- Retrieves check address from PoolFactory via `IPoolFactory(factory).valueManipulationCheck()`
- Value checks are performed after calculating fund value changes
- Operation type checks are performed at the start of each operation

#### PoolFactory.sol (Solidity 0.7.6)

- Adds `valueManipulationCheck` state variable
- Adds `setValueManipulationCheck(address)` setter function (owner only)
- Provides check address to all pools via `valueManipulationCheck()` view function

## Lending Market Integration

This implementation enables dHEDGE vaults to be safely listed on lending markets by:

1. ✅ Preventing atomic value manipulation attacks
2. ✅ Making flashloan-based exploits unprofitable
3. ✅ Protecting lending market LPs from bad debt
