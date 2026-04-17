# EasyLimitBuyManager - Order Price Parameters Guide

This document explains how to configure `minTriggerPriceD18` and `maxTriggerPriceD18` parameters in limit buy orders for different trading strategies.

## Overview

The `LimitBuyOrder` struct contains two price bounds that control when an order can be executed:

```solidity
struct LimitBuyOrder {
  address owner; // User address that created the order
  address targetVault; // dHEDGE vault to deposit into
  address pricingAsset; // Asset whose price triggers execution (e.g., WBTC, WETH)
  uint256 minTriggerPriceD18; // Lower price bound (18 decimals)
  uint256 maxTriggerPriceD18; // Upper price bound (18 decimals)
  uint16 slippageToleranceBps; // Slippage tolerance in basis points
}
```

**Execution condition:** An order can only be filled when:

```
minTriggerPriceD18 <= currentPrice <= maxTriggerPriceD18
```

## Trading Strategies

### 1. Buy the Dip (Traditional Limit Buy)

**Intent:** "I want to buy this vault when the pricing asset drops to a certain price or lower."

This is the most common limit buy strategy - accumulating at lower prices.

| Parameter            | Value            | Explanation                                                 |
| -------------------- | ---------------- | ----------------------------------------------------------- |
| `minTriggerPriceD18` | `0`              | No lower bound - accept any price at or below max           |
| `maxTriggerPriceD18` | Target dip price | The ceiling - order executes when price drops to this level |

**Example 1 (BULL vault):** Buy BTCBULL vault when BTC drops to $80,000

_Strategy: Accumulate leveraged long tokens at a discount, expecting BTC to recover._

```solidity
LimitBuyOrder({
    owner: USER_ADDRESS,
    targetVault: BTCBULL_VAULT,
    pricingAsset: WBTC,
    minTriggerPriceD18: 0,                    // No floor
    maxTriggerPriceD18: 80_000e18,            // Execute at $80k or below
    slippageToleranceBps: 100                 // 1% slippage
})
```

**Example 2 (BEAR vault):** Buy BTCBEAR vault when BTC drops to $80,000

_Strategy: Momentum play - BTC is already falling, buy BEAR tokens to profit from continued downside._

```solidity
LimitBuyOrder({
    owner: USER_ADDRESS,
    targetVault: BTCBEAR_VAULT,
    pricingAsset: WBTC,
    minTriggerPriceD18: 0,                    // No floor
    maxTriggerPriceD18: 80_000e18,            // Execute at $80k or below
    slippageToleranceBps: 100                 // 1% slippage
})
```

**When it executes:**

- ✅ BTC at $79,000 → Executes (79k ≤ 80k)
- ✅ BTC at $80,000 → Executes (80k ≤ 80k)
- ❌ BTC at $85,000 → Reverts (85k > 80k)

---

### 2. Buy the Breakout

**Intent:** "I want to buy this vault when the pricing asset breaks above a resistance level."

Momentum strategy - buying into strength after price confirms upward movement.

| Parameter            | Value               | Explanation                                            |
| -------------------- | ------------------- | ------------------------------------------------------ |
| `minTriggerPriceD18` | Breakout price      | The floor - order executes when price rises above this |
| `maxTriggerPriceD18` | `type(uint256).max` | No upper bound - accept any price at or above min      |

**Example 1 (BULL vault):** Buy ETHBULL vault when ETH breaks above $4,000

_Strategy: Trend-following - ride the momentum of a confirmed upward breakout._

```solidity
LimitBuyOrder({
    owner: USER_ADDRESS,
    targetVault: ETHBULL_VAULT,
    pricingAsset: WETH,
    minTriggerPriceD18: 4_000e18,             // Execute at $4k or above
    maxTriggerPriceD18: type(uint256).max,    // No ceiling
    slippageToleranceBps: 100                 // 1% slippage
})
```

**Example 2 (BEAR vault):** Buy ETHBEAR vault when ETH breaks above $4,000

_Strategy: Accumulate BEAR tokens at a discount (they're cheap when ETH is high), expecting a reversal._

```solidity
LimitBuyOrder({
    owner: USER_ADDRESS,
    targetVault: ETHBEAR_VAULT,
    pricingAsset: WETH,
    minTriggerPriceD18: 4_000e18,             // Execute at $4k or above
    maxTriggerPriceD18: type(uint256).max,    // No ceiling
    slippageToleranceBps: 100                 // 1% slippage
})
```

**When it executes:**

- ❌ ETH at $3,800 → Reverts (3.8k < 4k)
- ✅ ETH at $4,000 → Executes (4k ≥ 4k)
- ✅ ETH at $4,500 → Executes (4.5k ≥ 4k)

---

### 3. Buy Within a Range (Advanced)

**Intent:** "Buy the dip, but not during a flash crash or black swan event."

Sets both floor and ceiling for edge cases like avoiding panic crashes or oracle manipulation.

| Parameter            | Value       | Explanation                                |
| -------------------- | ----------- | ------------------------------------------ |
| `minTriggerPriceD18` | Lower bound | Floor - don't buy if price crashes too far |
| `maxTriggerPriceD18` | Upper bound | Ceiling - don't buy above this price       |

**Example:** Buy BTCBULL only if BTC is between $75k-$85k (avoid flash crash below $75k)

```solidity
LimitBuyOrder({
    owner: USER_ADDRESS,
    targetVault: BTCBULL_VAULT,
    pricingAsset: WBTC,
    minTriggerPriceD18: 75_000e18,            // Floor at $75k
    maxTriggerPriceD18: 85_000e18,            // Ceiling at $85k
    slippageToleranceBps: 100                 // 1% slippage
})
```

> 💡 **Note:** Most users will use "Buy the Dip" or "Buy the Breakout" patterns. Range is for advanced protection scenarios.

---

### 4. Market Order (Any Price)

**Intent:** "I want to buy this vault regardless of current price - just execute as soon as possible."

Immediate execution - the keeper can fill this order at any time.

| Parameter            | Value               | Explanation      |
| -------------------- | ------------------- | ---------------- |
| `minTriggerPriceD18` | `0`                 | Accept any price |
| `maxTriggerPriceD18` | `type(uint256).max` | Accept any price |

**Example:** Buy BTCBULL vault at any BTC price

```solidity
LimitBuyOrder({
    owner: USER_ADDRESS,
    targetVault: BTCBULL_VAULT,
    pricingAsset: WBTC,
    minTriggerPriceD18: 0,                    // No floor
    maxTriggerPriceD18: type(uint256).max,    // No ceiling
    slippageToleranceBps: 100                 // 1% slippage
})
```

**When it executes:** Always, at any price.

---

## Invalid Configurations

### Guarded (Reverts with Specific Error)

| Configuration         | Error               | Description                                    |
| --------------------- | ------------------- | ---------------------------------------------- |
| `minPrice > maxPrice` | `InvalidPriceRange` | Invalid range - fails early with clear message |

### Never Executable Orders

These configurations have valid ranges but will never match real prices:

| Configuration                             | Why It Fails                                                     |
| ----------------------------------------- | ---------------------------------------------------------------- |
| `minPrice = maxPrice = 0`                 | Only executes if price is exactly 0 (impossible for real assets) |
| `minPrice = maxPrice = type(uint256).max` | Only executes if price is exactly max uint256 (impossible)       |

---

## Quick Reference

| Strategy         | minTriggerPriceD18 | maxTriggerPriceD18  |
| ---------------- | ------------------ | ------------------- |
| Buy the Dip      | `0`                | Target dip price    |
| Buy the Breakout | Breakout price     | `type(uint256).max` |
| Buy in Range     | Lower bound        | Upper bound         |
| Market Order     | `0`                | `type(uint256).max` |

---

## Price Decimals

All prices use 18 decimals (`D18` suffix). Examples:

- `$1.00` → `1e18` (1000000000000000000)
- `$1,000` → `1_000e18`
- `$80,000` → `80_000e18`
- `$0.50` → `0.5e18` or `5e17`
