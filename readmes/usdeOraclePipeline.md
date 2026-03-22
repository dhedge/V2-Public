# USDe and sUSDe Oracle Pipeline

This document explains how the oracle configurations for USDe and sUSDe work together.

## Overview

Both USDe and sUSDe use `ChainlinkTWAPAggregator`, which combines two independent price sources and validates them against each other.

## Architecture Diagram

```
+-------------------------------------------------------------------------------------------+
|                                    USDe Oracle Pipeline                                   |
+-------------------------------------------------------------------------------------------+
|                                                                                           |
|   +------------------------------+        +-------------------------------------------+   |
|   |       Chainlink Oracle       |        |      FluidDexObservationAggregator        |   |
|   |                              |        |                                           |   |
|   |                              |        |                                           |   |
|   |   - External USDe/USD feed   |        |   - Reads USDe/USDT from Fluid DEX pool   |   |
|   |   - Standard Chainlink API   |        |   - Computes TWAP from observations       |   |
|   +---------------+--------------+        |   - Validates volatility on record        |   |
|                   |                       +---------------------+---------------------+   |
|                   |                                             |                         |
|                   v                                             v                         |
|          +-----------------------------------------------------------------------+        |
|          |                      ChainlinkTWAPAggregator                          |        |
|          |                                                                       |        |
|          |   1. Fetch chainlinkPrice from Chainlink Oracle                       |        |
|          |   2. Fetch twapPrice from FluidDexObservationAggregator               |        |
|          |   3. Check: |chainlinkPrice - twapPrice| <= 0.5% of min price         |        |
|          |   4. Return: MAX(chainlinkPrice, twapPrice) [resultingPriceType=0]    |        |
|          |                                                                       |        |
|          |   If TWAP fails -> fallback to chainlinkPrice only                    |        |
|          +-----------------------------------------------------------------------+        |
|                                                                                           |
+-------------------------------------------------------------------------------------------+


+-------------------------------------------------------------------------------------------+
|                                   sUSDe Oracle Pipeline                                   |
+-------------------------------------------------------------------------------------------+
|                                                                                           |
|   +-----------------------------------------------------------------------+               |
|   |                       ERC4626PriceAggregator                          |               |
|   |                                                                       |               |
|   |   1. Get USDe price from AssetHandler's registered oracle             |               |
|   |   2. Get sUSDe->USDe exchange rate: convertToAssets(1e18)             |               |
|   |   3. Return: USDe_price x exchange_rate                               |               |
|   |                                                                       |               |
|   |   +---------------------------------------------------------------+   |               |
|   |   |   USDe Oracle (from AssetHandler)                             |   |               |
|   |   |   The USDe ChainlinkTWAPAggregator shown above                |   |               |
|   |   +---------------------------------------------------------------+   |               |
|   +----------------------------------+------------------------------------+               |
|                                      |                                                    |
|                                      |       +----------------------------------------+   |
|                                      |       |    FluidDexObservationAggregator       |   |
|                                      |       |                                        |   |
|                                      |       |                                        |   |
|                                      |       |    - Reads sUSDe/USDT from Fluid DEX   |   |
|                                      |       |    - Computes TWAP from observations   |   |
|                                      |       +-------------------+--------------------+   |
|                                      |                           |                        |
|                                      v                           v                        |
|          +-----------------------------------------------------------------------+        |
|          |                      ChainlinkTWAPAggregator                          |        |
|          |                                                                       |        |
|          |   1. Fetch erc4626Price from ERC4626PriceAggregator                   |        |
|          |   2. Fetch twapPrice from FluidDexObservationAggregator               |        |
|          |   3. Check: |erc4626Price - twapPrice| <= 0.4% of min price           |        |
|          |   4. Return: twapPrice [resultingPriceType=3]                         |        |
|          |                                                                       |        |
|          |   If TWAP fails -> fallback to erc4626Price only                      |        |
|          +-----------------------------------------------------------------------+        |
|                                                                                           |
+-------------------------------------------------------------------------------------------+
```

### USDe Parameter Breakdown

| Parameter                    | Value              | Meaning                                          |
| ---------------------------- | ------------------ | ------------------------------------------------ |
| `chainlinkAggregatorAddress` | `0xa569d910...`    | External Chainlink oracle for USDe/USD           |
| `maxPriceDifferencePercent`  | `5000000000000000` | 0.5% (5e15 / 1e18 = 0.005)                       |
| `resultingPriceType`         | `0` (MAX)          | Return the **higher** of the two prices          |
| `twapAggregatorAddress`      | `0xF0ABfb56d...`   | FluidDexObservationAggregator for USDe/USDT pool |

### Price Resolution Logic

```
1. chainlinkPrice = chainlinkAggregator.latestRoundData()
   → External oracle price (e.g., $0.9985)

2. try twapAggregator.latestRoundData()
   → FluidDexObservationAggregator computes TWAP from stored observations
   → Returns TWAP price (e.g., $0.9990)

3. Check deviation:
   priceDiff = |chainlinkPrice - twapPrice|
   minPrice = min(chainlinkPrice, twapPrice)
   differencePercent = priceDiff / minPrice

   REQUIRE: differencePercent <= 0.5%

4. Return MAX(chainlinkPrice, twapPrice)
   → Conservative: protects dHEDGE from undervaluation during deposits

5. If TWAP fails → Return chainlinkPrice only (fallback)
```

---

### sUSDe Parameter Breakdown

| Parameter                   | Value                      | Meaning                                                 |
| --------------------------- | -------------------------- | ------------------------------------------------------- |
| `chainlinkType`             | `"ERC4626PriceAggregator"` | Deploy ERC4626PriceAggregator as the "chainlink" source |
| `dhedgeFactoryProxy`        | `0x96D33bCF...`            | Used to get AssetHandler for dynamic oracle lookup      |
| `maxPriceDifferencePercent` | `4000000000000000`         | 0.4% (4e15 / 1e18 = 0.004)                              |
| `resultingPriceType`        | `3` (TWAP)                 | **Always use TWAP price**                               |
| `twapAggregatorAddress`     | `0xFc3b21529D...`          | FluidDexObservationAggregator for sUSDe pool            |

### Price Resolution Logic

```
--- ERC4626PriceAggregator (acts as "chainlink" source) ---

1. underlyingPrice = assetHandler.priceAggregators(USDe).latestRoundData()
   → Gets USDe price from the USDe ChainlinkTWAPAggregator above
   → Example: $0.9990

2. exchangeRate = sUSDe.convertToAssets(1e18)
   → How much USDe you get for 1 sUSDe
   → Example: 1.05e18 (1 sUSDe = 1.05 USDe)

3. erc4626Price = underlyingPrice × exchangeRate / 1e18
   → Example: $0.9990 × 1.05 = $1.0490

--- ChainlinkTWAPAggregator ---

4. twapPrice = twapAggregator.latestRoundData()
   → FluidDexObservationAggregator computes TWAP for sUSDe
   → Example: $1.0485

5. Check deviation:
   REQUIRE: |erc4626Price - twapPrice| <= 0.4% of min price
   → |$1.0490 - $1.0485| = $0.0005
   → $0.0005 / $1.0485 = 0.047% ✓ (passes)

6. Return twapPrice [resultingPriceType=3]
   → Always returns the TWAP price ($1.0485)

7. If TWAP fails → Return erc4626Price only (fallback)
```

---

## FluidDexObservationAggregator Deep Dive

Both USDe and sUSDe use FluidDexObservationAggregator for their TWAP source. This oracle:

### How It Works

1. **Observation Recording** (via Chainlink Automation):

   ```
   recordObservation()
   ├── Check minObservationInterval since last observation
   ├── Fetch current price from Fluid DEX pool
   ├── Validate against TWAP (volatility check)
   └── Store in circular buffer
   ```

2. **TWAP Calculation** (on `latestRoundData()`):
   ```
   _computeTwap()
   ├── Walk backwards through observations within twapPeriod
   ├── Compute time-weighted average
   ├── Require at least 2 full segments
   └── Return TWAP × pairToken USD price
   ```

### Key Parameters (Typical Values)

| Parameter                | Value        | Purpose                           |
| ------------------------ | ------------ | --------------------------------- |
| `twapPeriod`             | 12 hours     | Window for TWAP calculation       |
| `minObservationInterval` | 15 minutes   | Minimum gap between observations  |
| `maxStaleness`           | 10 hours     | Maximum age of latest observation |
| `volatilityLimit`        | 300 bps (3%) | Max deviation from TWAP on record |
| `bufferSize`             | 64           | Observations stored               |
