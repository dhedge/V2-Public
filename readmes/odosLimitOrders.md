# Odos Limit Orders for dHEDGE Pools

## Overview

This feature allows dHEDGE pool managers to create Odos limit orders on behalf of their pools. Orders are signed using ERC-1271 signatures and validated through the `TypedStructuredDataValidator` contract.

## Architecture

```
┌─────────────────────┐     ┌──────────────────────────────┐
│   Pool Manager      │     │  TypedStructuredDataValidator│
│   (calls submit)    │────▶│  (validates & stores hash)   │
└─────────────────────┘     └──────────────────────────────┘
                                         │
                                         ▼
                            ┌──────────────────────────────┐
                            │  OdosLimitOrderValidator     │
                            │  (validates order structure) │
                            └──────────────────────────────┘
                                         │
                                         ▼
┌─────────────────────┐     ┌──────────────────────────────┐
│   Odos Filler       │────▶│  PoolLogic.isValidSignature  │
│   (executes order)  │     │  (checks validatedHashes)    │
└─────────────────────┘     └──────────────────────────────┘
```

## Order Flow

1. **Manager submits order**: Calls `TypedStructuredDataValidator.submit()` with the EIP-712 typed data
2. **Validation**: `OdosLimitOrderValidator` validates:
   - Domain is "Permit2" on correct chain
   - Spender is the Odos limit order router
   - Input/output tokens are supported by the pool
   - Rate is not unfavorable (see Rate Protection below)
3. **Hash storage**: The EIP-712 hash is stored in `validatedHashes[pool][hash] = true`
4. **Token locking**: Input and output tokens are added to `orderTokens` to prevent being disabled
5. **Order execution**: When Odos filler calls `fillLimitOrderPermit2()`, it requests ERC-1271 signature verification
6. **Signature check**: `PoolLogic.isValidSignature()` → `TypedStructuredDataValidator.isValidatedHash()` checks if hash is validated
7. **Cleanup**: When a new order is submitted, `_cleanupExpiredOrders()` removes orders past their expiry and unlocks tokens. Note: Permit2 handles replay protection for executed orders via nonces.

## Rate Protection

### Why It's Needed

Odos limit orders specify **amounts, not prices**. The smart contract only ensures the user receives their minimum output amount - it doesn't check if the rate is favorable.

In Odos's system, whitelisted fillers will immediately fill any order that is profitable for them - including unfavorable orders where the user receives less value than they give. For dHEDGE pools with untrusted managers, we need on-chain protection to prevent managers from creating such exploitable orders.

### How It Works

At order submission time, we check that the order rate is not significantly worse than current oracle prices:

```
outputValueUSD >= inputValueUSD * (1 - maxUnfavorableDeviationBps / 10000)
```

Default tolerance: **1%** (100 bps) to account for oracle staleness and timing differences.

### Rate Validation Examples

All examples use **WETH** (18 decimals) and **USDC** (6 decimals).

#### Example 1: Take Profit Order - ALLOWED ✅

**Scenario**: Manager wants to sell ETH at a higher price than current market.

| Parameter          | Value                       |
| ------------------ | --------------------------- |
| Current ETH Price  | $4,000                      |
| Order              | Sell 1 ETH → Get 5,000 USDC |
| Implied Order Rate | $5,000/ETH                  |

**Calculation**:

- Input value: 1 ETH × $4,000 = $4,000
- Output value: 5,000 USDC × $1 = $5,000
- Check: $5,000 ≥ $4,000 × 0.99 ($3,960) ✅

**Result**: Order is ALLOWED. Manager is asking for MORE than market rate.

---

#### Example 2: Stop Loss Order - BLOCKED ❌

**Scenario**: Manager wants to create a stop-loss at $3,000.

| Parameter          | Value                       |
| ------------------ | --------------------------- |
| Current ETH Price  | $4,000                      |
| Order              | Sell 1 ETH → Get 3,000 USDC |
| Implied Order Rate | $3,000/ETH                  |

**Calculation**:

- Input value: 1 ETH × $4,000 = $4,000
- Output value: 3,000 USDC × $1 = $3,000
- Check: $3,000 ≥ $4,000 × 0.99 ($3,960) ❌

**Result**: Order is BLOCKED with `OrderRateTooUnfavorable`.

**Why blocked?** This order could be filled immediately by anyone, taking $4,000 worth of ETH and giving back only $3,000 USDC - a $1,000 loss to the pool.

---

#### Example 3: Market Rate Order - ALLOWED ✅

**Scenario**: Manager creates an order at approximately current market rate.

| Parameter          | Value                       |
| ------------------ | --------------------------- |
| Current ETH Price  | $4,000                      |
| Order              | Sell 1 ETH → Get 3,980 USDC |
| Implied Order Rate | $3,980/ETH                  |

**Calculation**:

- Input value: 1 ETH × $4,000 = $4,000
- Output value: 3,980 USDC × $1 = $3,980
- Check: $3,980 ≥ $4,000 × 0.99 ($3,960) ✅

**Result**: Order is ALLOWED. Within 1% tolerance of market rate.

---

#### Example 4: Slightly Below Market - ALLOWED ✅

**Scenario**: Order at 0.5% below market (within tolerance).

| Parameter         | Value                       |
| ----------------- | --------------------------- |
| Current ETH Price | $4,000                      |
| Order             | Sell 1 ETH → Get 3,980 USDC |
| Deviation         | -0.5%                       |

**Calculation**:

- Input value: $4,000
- Output value: $3,980
- Required minimum: $4,000 × 0.99 = $3,960
- Check: $3,980 ≥ $3,960 ✅

**Result**: Order is ALLOWED.

---

#### Example 5: Beyond Tolerance - BLOCKED ❌

**Scenario**: Order at 2% below market (beyond 1% tolerance).

| Parameter         | Value                       |
| ----------------- | --------------------------- |
| Current ETH Price | $4,000                      |
| Order             | Sell 1 ETH → Get 3,920 USDC |
| Deviation         | -2%                         |

**Calculation**:

- Input value: $4,000
- Output value: $3,920
- Required minimum: $4,000 × 0.99 = $3,960
- Check: $3,920 ≥ $3,960 ❌

**Result**: Order is BLOCKED.

---

#### Example 6: Buying ETH (Reverse Direction) - ALLOWED ✅

**Scenario**: Manager wants to buy ETH at a lower price.

| Parameter         | Value                       |
| ----------------- | --------------------------- |
| Current ETH Price | $4,000                      |
| Order             | Sell 3,000 USDC → Get 1 ETH |
| Implied Buy Rate  | $3,000/ETH                  |

**Calculation**:

- Input value: 3,000 USDC × $1 = $3,000
- Output value: 1 ETH × $4,000 = $4,000
- Check: $4,000 ≥ $3,000 × 0.99 ($2,970) ✅

**Result**: Order is ALLOWED. Manager is trying to BUY cheaper than market.

## Token Locking

When an order is submitted:

- The input token is added to `orderTokens[pool]`
- This prevents the token from being disabled while the order is active
- When the order expires or is executed, cleanup removes the lock

## Order Limits

- **MAX_ORDERS_PER_POOL**:
- Ensures bounded gas costs
- Expired orders are automatically cleaned up during new submissions

## Configuration

The validator config is set per chain:

```solidity
struct OdosLimitOrderValidationConfig {
  address verifyingContract; // Permit2 address
  address spender; // Odos limit order router
  uint16 maxUnfavorableDeviationBps; // Default: 100 (1%)
}
```
