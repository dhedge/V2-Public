# Pendle Finance Protocol

## Principal Token Integration

### Example transactions from [the app](https://app.pendle.finance/trade/markets):

#### Arbitrum

1. [Approve spending USDC](https://arbiscan.io/tx/0x706b6577b3f798b10970028ec5c87afce7aea13796e7efdf1c176073f3007a60)
2. [Buy PT weETH](https://arbiscan.io/tx/0x2b23d23f5b0c90ef6f385cab23072abfbcc55aabc7a00077208026a4e0cff5bd)
3. [Approve spending PT sUSDS](https://arbiscan.io/tx/0x8294ce6cd7de23711c1a54fdb2c6470b979041533eff7fd2c6c5488a9d11155c)
4. [Sell PT sUSDS for sUSDS](https://arbiscan.io/tx/0x99b9b677583ea4212e884dddecea86664d9089e178382b5904bfefc89af85f70)
5. [Sell PT sUSDS for USDC](https://arbiscan.io/tx/0xbb64bd12ee40d2d4328fd9b2ffcba81b80b3481c0666cd5c7fec4b114ab49330)
6. [Sell PT sUSDS for WETH](https://arbiscan.io/tx/0xfe9bbdafbe4ccf3c44b2810855402e391a9e706ef767b5a61aff46671c7c2b3c)

- [PT-sUSDS-28AUG2025](https://arbiscan.io/address/0xBDcf887B8c8aC9FB27876C5376695008b13dbC63)
- [sUSDS Market](https://arbiscan.io/address/0xff4d6991658c5844856faef5da9232c252896fca#code)
- [weETH Market](https://arbiscan.io/address/0xbf5e60ddf654085f80dae9dd33ec0e345773e1f8)

#### Base

1. [Approve spending moonwell USDC](https://basescan.org/tx/0xc7bad6b3fd636ea6275d29fec3046e9105a3408874630f8007c04084c81c87e9)
2. [Buy PT mUSDC](https://basescan.org/tx/0xb54f3e2e05d7783a3856d81441c9886716eb0b9513f8cf3ffe2d60c9f96fbb16)
3. [Approve spending USDC](https://basescan.org/tx/0xa93a732bbac935bfd2557840e7de9a396da8ccd20ee712cebf8a87d71531d3a6)
4. [Buy PT Resolv USR](https://basescan.org/tx/0xbebae678a1aeaeece15e30871e56c998ced7c2f1e5c5e39231b1de329d45278e)
5. [Sell expired PT Resolv USR](https://basescan.org/tx/0xaa525f9ef10278de32764931a146b63c5ca6f0b8f8a9df904286b018d31df96e)
6. [Swap PT for SY](https://basescan.org/tx/0x42657c318ed4a0190af479fa0dd46d155832caf4b149041f6c12c8a0f2fac61d)
7. [Redeem SY to underlying](https://basescan.org/tx/0x439987da334e803c2948a86ded636cbc975f98f0152db48f0e2af6b71cb8403f), note: `minTokenOut` param matters only when redeeming SY to other token than underlying. When redeeming to underlying, `minTokenOut` is not taken into account and can be set to any value, redeeming happens 1:1. [Source code proving the above.](https://github.com/pendle-finance/pendle-core-v2-public/blob/main/contracts/router/base/ActionBase.sol#L119)

### Integration Overview

Provides contract guard for Pendle Router, which allows buying and selling PTs inside the dHEDGE vault.

Swaps are disabled, as we can always swap during deposit into vault while having underlying yield token set as deposit asset. This can be changed later if strictly necessary, but will make guard checks much more complicated and strict.

Limit orders are disabled as well.

Vaults can only buy PTs which are added to `AssetHandler` by dHEDGE DAO.

To buy PT, vault needs to have it enabled. In order to sell PT, vault needs to have underlying yield token enabled.

### Withdraw Processing

PTs are withdrawn as regular ERC20 tokens (WETH, USDC, etc.) If strictly necessary, it's possible to add redeeming to underlying during withraw processing, otherwise it can be implemented inside `EasySwapperV2`.

### PTs Rricing

1. [SY Docs](https://docs.pendle.finance/Developers/Contracts/StandardizedYield#standard-sys)
2. [Oracle Docs](https://docs.pendle.finance/Developers/Oracles/HowToIntegratePtAndLpOracle)
3. [Example how to price PT](https://github.com/pendle-finance/pendle-core-v2-public/blob/main/contracts/oracles/PtYtLpOracle/samples/BoringPYUsdChainlinkSYOracle.sol)

This is why SY 1:1 wrap of yield token: [see SY Contract](https://basescan.org/address/0x239ce1472358968290e6e3bb5c2d51ee0709e008#code). See `deposit` and `redeem` functions.

`PendleChainlinkOracleFactory` allows creating `PendleChainlinkOracle` contracts.

[PendleChainlinkOracleFactory on Base](https://basescan.org/address/0x2a73e899389caba2a2f648baba35e67f5c00efee).

Can check if already exists, if not - can create.

`baseOracleType` should use `0` in most of the cases (as per docs above). Will price in terms of SY token, which can be priced in terms of underlying yield token.

`twap` The recommended duration is 15 mins (900 secs) or 30 mins (1800 secs), but it can vary depending on the market. `checkOracleState` is called during oracle creation: `@notice Call only once for each (market, duration). Once successful, it's permanently valid (also for any shorter duration).`

`PendlePTPriceAggregator` accepts underlying yield token address instead of its oracle address and has `updateUnderlyingAggregator` public function implemented. This is because previously we used to pass oracle address which later could become outdated and lead to bugs in oracles depending on them. Having update function can improve the process, eliminating the need to redeploy dependant oracles. If it make sense, can refactor Fluid oracle using same pattern and create some scripts.

### Tests

Each new market dHEDGE DAO is keen to add needs to run the tests against before deployment.
