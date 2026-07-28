# Ondo GM Withdrawal

Ondo GM is integrated as **asset type 41**. dHEDGE pools can hold GM in two places, and both flows redeem GM → USDC via the same swap gateway (`OndoGMSwap`), which intermediates between the caller and Ondo's `GMTokenManager`:

| Path                  | Where GM lives                                | Caller of the swap                                | Anchor for `quote.quantity`                     |
| --------------------- | --------------------------------------------- | ------------------------------------------------- | ----------------------------------------------- |
| **Direct** (asset 41) | In the pool's supportedAssets list            | The pool (via `PoolLogic`)                        | Depositor's pro-rata share of pool's GM balance |
| **DYTM collateral**   | Inside a DYTM Office account (asset type 106) | The `WithdrawalVault` (via DYTM `delegationCall`) | Per-position split-account GM amount            |

Both paths build the same `[approve, swapExactInWithAttestation]` calldata pair. They differ only in **who initiates the swap** and **how the per-withdrawal GM amount is computed**.

The integration consists of:

1. **Asset guard** (`OndoGMTokenAssetGuard`) — 4-arg `withdrawProcessing` reverts; the 5-arg `IComplexAssetGuard` overload validates the user's payload and returns the approve + swap transactions.
2. **Swap gateway** (`OndoGMSwap`) — atomic mint / redeem against Ondo's `GMTokenManager`.

The DYTM-collateral flow has no Ondo-specific contract — the Ondo swap is just one of many actions in a frontend-built `UnwindPlan` that the generic DYTM-unwind dispatcher (`DytmWithdrawLib.processDytmPosition`) executes as a multicall.

---

## 1. Direct Path

When a pool holds GM directly, withdrawal redeems the depositor's portion of GM into USDC atomically inside `PoolLogic._withdrawProcessing`.

```
User                                              Pool / asset guard
   │
   │── withdrawSafe(amount, complexAssetsData) ─►│
   │   complexAssetsData[i] for the GM slot:      │
   │     supportedAsset = GM token                │
   │     withdrawData = abi.encode(               │
   │       OndoWithdrawData{                      │
   │         attestationSignature,                │
   │         quote,                               │
   │         amountOutMinimum                     │
   │       })                                     │
   │                                              │
   │                                              │  PoolLogic._withdrawTo:
   │                                              │   for each supported asset i:
   │                                              │     OndoGMTokenAssetGuard.withdrawProcessing
   │                                              │       • assert quote.quantity within delta
   │                                              │         of portion-scaled GM balance
   │                                              │       • assert amountOutMinimum floor
   │                                              │       • return [approve, swap] txs
   │                                              │   pool executes returned txs
   │                                              │   (msg.sender of swap = pool):
   │                                              │     OndoGMSwap.swapExactInWithAttestation
   │                                              │       redeem GM → USDC at the pool
   │                                              │   PoolLogic balance-diff measures ΔUSDC
   │                                              │   on the pool, transfers it to the user
   │◄────────── USDC ────────────────────────────┤
```

### Frontend pre-flight

There is **no on-chain calculator** for the direct path. The frontend computes the redemption amount client-side using:

1. Simulate `pool.mintManagerFee()` via `eth_call` so totalSupply reflects the about-to-be-minted manager fee.
2. Read `poolManagerLogic.getExitFeeInfo()` and discount the withdrawal amount by the exit fee.
3. `portion = adjustedAmount × 1e18 / pool.totalSupply()`.
4. For each GM the pool holds: `amount = IERC20(gm).balanceOf(pool) × portion / 1e18`.

That `amount` is what the frontend requests an Ondo attestation for — it must equal `quote.quantity` within `mismatchDeltaNumerator` for the on-chain check below to pass.

### Defence-in-depth checks (direct path only)

The 5-arg `withdrawProcessing` carries two checks that pair with PoolLogic's net-slippage tolerance:

- **`quote.quantity` within delta** — must not exceed the depositor's portion-scaled GM balance, and any undershoot must fall within `mismatchDeltaNumerator`. One-sided: a `quote.quantity` _greater than_ the portion would redeem more GM than the user is entitled to and is rejected outright. Small undershoots absorb sim → exec drift; any leftover GM stays in the pool.
- **`amountOutMinimum` floor** — bounds how aggressively a frontend can understate the USDC floor. The cap is `MAX_AMOUNT_OUT_MIN_DISCOUNT_BPS = 100` (1%) below the deterministic USDon redemption value (`quote.quantity × quote.price / 1e18`). Prevents pairing a large slippage tolerance with a near-zero `amountOutMinimum` to sidestep PoolLogic's net-slippage check.

The 4-arg `withdrawProcessing` overload always reverts — Ondo always requires a signed attestation; raw GM is never delivered.

---

## 2. DYTM-Collateral Path

When GM lives inside a DYTM Office account as collateral (asset type 106 at the pool level), withdrawal goes through EasySwapperV2's generic DYTM-unwind dispatcher. The dispatcher does not know anything about Ondo specifically — it just executes a frontend-built `UnwindPlan.actions[]` as a flat multicall inside a DYTM `delegationCall`, then enforces drain and slippage post-conditions. See [`dytm-integration.md`](./dytm-integration.md) for the full mechanics.

### End-to-end flow

```
User
  │
  │── EasySwapperV2.initWithdrawal(pool, amount, complexAssetsData)
  │     complexAssetsData[i] for the DYTM Office slot:
  │       supportedAsset = dytmOffice
  │       withdrawData   = abi.encode(DytmWithdrawLib.UnwindPlan{
  │                          actions, outputAsset, minOutputAmount
  │                        })
  │
  │── (later) EasySwapperV2.completeWithdrawal()
  │            │
  │            │── PoolLogic.withdrawToSafe(vault, ...)
  │            │     • DytmOfficeAssetGuard.withdrawProcessing
  │            │         splits the DYTM accounts proportionally
  │            │         transfers split accounts to the WithdrawalVault
  │            │
  │            │── WithdrawalVault.unrollAssets(...)
  │                  • DytmWithdrawLib.processDytmPosition
  │                      decodes UnwindPlan, snapshots outputAsset balance
  │                      delegationCall(vault as delegatee)
  │                        └─ WithdrawalVault.onDelegationCallback
  │                              executes actions[]:
  │                                IDytmOffice.withdraw(...)             // each GM collateral
  │                                IERC20(gm).approve(ondoGMSwap, ...)
  │                                OndoGMSwap.swapExactInWithAttestation  // GM → USDC
  │                                IERC20(debtAsset).approve(...)         // (if debt)
  │                                IDytmOffice.repay(...)                 // (if debt)
  │                      post: every transferred split account is drained
  │                      post: vault outputAsset gain ≥ minOutputAmount
  └◄── outputAsset transferred to user
```

The dispatcher is a generic multicall executor — there are no on-chain branches on "Ondo vs other" or "debt vs no-debt." Whatever sequence of DYTM actions and external calls the unwind needs, the frontend lists them in `actions[]`. Safety comes from three on-chain post-checks:

1. **Drained accounts** — every split account must end the delegation call with zero collateral IDs and zero debt ID. Otherwise value would be orphaned inside an empty-but-still-owned account NFT.
2. **Slippage floor** — `outputAsset` balance gain ≥ `UnwindPlan.minOutputAmount`. This is the only economic gate on the opaque action plan; the frontend sets it from its predicted unwind value minus the user's slippage tolerance.
3. **Atomicity** — any revert inside `actions[]`, the drain check, or the slippage check rolls back the whole `completeWithdrawal`.

### Frontend planning for the DYTM path

The frontend uses **`DytmWithdrawalCalculator.previewWithdrawal(pool, amount)`** (callStatic; guarded with `cannotExecute`) to get a flat `DytmParamStructs.AssetData[]` covering every collateral and every non-zero debt across all withdrawable DYTM markets. Each entry carries:

- Asset address + portion-scaled amount + asset type + `isPool` flag (for dHEDGE-vault collaterals).
- An `isDebt` flag distinguishing collateral from debt slots.
- DYTM action identifiers: `marketId`, `accountId` (already shifted by 160 bits), `tokenId` (collateral) or `debtKey` (debt), `shares`.

For each entry with `assetType == 41`, the frontend fetches a signed Ondo attestation sized to `amount` and assembles an `[approve(GM, ondoGMSwap, amount), OndoGMSwap.swapExactInWithAttestation(...)]` action pair into `UnwindPlan.actions[]`. The action-construction fields (`accountId`, `tokenId`, `shares`) drop straight into `IDytmOffice.withdraw` / `repay` calldata.

There is no on-chain validation of "Ondo data shape" — the dispatcher only validates the final outcome (drain + slippage). Ondo-side rules are enforced by `OndoGMSwap` itself at swap time:

- `quote.asset == tokenIn` (asset mismatch revert).
- `amountIn == quote.quantity` (amount mismatch revert).
- `quote.side == SELL` for redemption.
- Ondo's `GMTokenManager` binds `msg.sender → userId` via `OndoIDRegistry` and rejects any attestation whose `userId` doesn't match.

### Comparison: validation surfaces

|                                      | Direct path                                                            | DYTM-collateral path                               |
| ------------------------------------ | ---------------------------------------------------------------------- | -------------------------------------------------- |
| Per-asset on-chain payload check     | `OndoGMTokenAssetGuard.withdrawProcessing` (delta + minOut floor)      | None — dispatcher doesn't parse action shapes      |
| Slippage gate                        | PoolLogic's net-slippage tolerance + on-chain `amountOutMinimum` floor | `UnwindPlan.minOutputAmount` over the whole unwind |
| Caller authorisation on `OndoGMSwap` | Pool calls (`msg.sender == pool`)                                      | Vault calls inside DYTM delegation                 |

In both cases the ultimate safety net is `OndoGMSwap`'s own checks (amount / asset / side) plus Ondo's userId-binding on `GMTokenManager`.

### Worked example: DYTM withdrawal of Ondo GM collateral with USDC debt

Concrete instantiation of the generic flow above for a single DYTM position holding GM as collateral against USDC debt. Exercised end-to-end by `test_dytmOndo_easySwapperV2_debtUsdcNoSwap_redeemsRepaysAndSettles` in `OndoGMDytmCollateralIntegrationTest.t.sol`.

**0. Planning (off-chain)**

```
Frontend ──callStatic──► DytmWithdrawalCalculator.previewWithdrawal(pool, poolTokenAmount)
         ◄── AssetData[] ─
            ├─ { asset=GM,   amount=X, isDebt=false, marketId, accountId, tokenId,  shares }
            └─ { asset=USDC, amount=D, isDebt=true,  marketId, accountId, debtKey,  shares }

Fetch signed Ondo attestation sized to X
  → { signature, quote{quantity=X, price, side=SELL}, amountOutMinimum }

Build UnwindPlan {
  actions: [
    (DytmOffice, withdraw(GM, accountId, tokenId, shares)),
    (GM,         approve(OndoGMSwap, X)),
    (OndoGMSwap, swapExactInWithAttestation(GM, X, USDC, amountOutMinimum, signature, quote)),
    (USDC,       approve(DytmOffice, D)),
    (DytmOffice, repay(USDC, accountId, debtKey, shares)),
  ],
  outputAsset:     USDC,
  minOutputAmount: floor on leftover USDC,
}
```

**1. `initWithdrawal` (tx 1)** — pool splits the user-portion DYTM account out and transfers the split account NFT to `WithdrawalVault`, as described in the generic flow.

**2. `completeWithdrawal` (tx 2)** — `WithdrawalVault.onDelegationCallback` runs `actions[]` sequentially as the account owner:

```
a) DytmOffice.withdraw(GM, …)              → vault holds GM
b) GM.approve(OndoGMSwap, X)
c) OndoGMSwap.swapExactInWithAttestation   → GM redeemed to USDC at vault
d) USDC.approve(DytmOffice, D)
e) DytmOffice.repay(USDC, …)               → debt cleared

Post-conditions:
  ✓ split account fully drained (0 collateral, 0 debt)
  ✓ vault USDC gain ≥ UnwindPlan.minOutputAmount

Leftover USDC transferred from vault → user.
```

User receives `redeemed GM value − D`. Any revert inside `actions[]` or in the post-checks rolls back the entire `completeWithdrawal`.

---

## 3. OndoGMSwap

`OndoGMSwap.swapExactInWithAttestation` has **no caller whitelist**. Any address can call it, because Ondo's `GMTokenManager` binds `msg.sender → userId` via `OndoIDRegistry` and rejects any attestation whose embedded `userId` doesn't match. A randomly-attacking address cannot forge an attestation tied to a different `userId`.

The contract still enforces three local invariants on every call:

- `quote.asset == tokenIn` (`AssetMismatch` revert).
- `amountIn == quote.quantity` (`AmountMismatch` revert).
- `quote.side` matches the operation (BUY for mint, SELL for redeem; `InvalidQuoteSide` otherwise).

After the swap, the actual USDC received is compared against `amountOutMinimum` (`InsufficientOutput` revert) and against the deterministic implied cost (`ExcessiveAmountIn` if exceeded — a defense against an `amountIn` that would consume more GM than the quote prices).

This open-caller model means there's no governance action required when a new caller (e.g. a new DYTM market on a new chain) wants to redeem GM — they just call.

---

## 4. Integration Testing

Today: Ondo GM is Ethereum-only; DYTM has no live Ethereum markets (Office is deployed but unused). The integration test resolves this by **mocking only the DYTM-side surface** (Office + Periphery + AccountSplitter) and keeping everything else real — `OndoGMSwap`, `OndoGMTokenAssetGuard`, `DytmOfficeAssetGuard`, `DytmWithdrawLib`, `EasySwapperV2`, `WithdrawalVault`, `PoolLogic`, plus a real signed Ondo attestation.

The shared setup (`OndoDytmCollateralIntegrationTestSetup`) wires up a synthetic DYTM market with a single GM collateral position, registers the asset guards, and exposes seed helpers for the no-debt / with-debt-USDC / with-debt-DAI variants. Each test calls `EasySwapperV2.initWithdrawal` → `completeWithdrawal` and asserts the investor receives the expected output asset.

Three scenarios across two test files:

**`OndoGMDytmCollateralIntegrationTest.t.sol`** (regular fork):

- `test_dytmOndo_easySwapperV2_noDebt_redeemsGMtoUSDC` — single GM collateral, no debt; `UnwindPlan` is `[withdraw(GM), approve(GM), swapExactInWithAttestation]`; output asset is USDC; investor receives USDC.
- `test_dytmOndo_easySwapperV2_debtUsdcNoSwap_redeemsRepaysAndSettles` — GM collateral + USDC debt; `UnwindPlan` is `[withdraw(GM), approve(GM), swapExactInWithAttestation, approve(USDC), repay(USDC)]`; output is the leftover USDC after repay.

**`OndoGMDytmCollateralIntegrationTest_FFI_Ethereum.t.sol`** (FFI fork, real Odos quote):

- `test_dytmOndo_easySwapperV2_debtDaiOdosSwap_redeemsSwapsRepaysAndSettles` — GM collateral + DAI debt; `UnwindPlan` is `[withdraw(GM), approve(GM), swapExactInWithAttestation, Odos USDC→DAI, approve(DAI), repay(DAI)]`. Exercises the full has-debt-with-swap path including the Odos aggregator leg.

**`OndoGMDirectWithdrawalTestEthereum.t.sol`** (direct path, no DYTM):

- Exercises `PoolLogic.withdrawSafe` against a pool holding GM directly. Asserts the `quote.quantity` mismatch tolerance, the `amountOutMinimum` floor cap, and the happy-path GM → USDC redemption.

The mocks are scoped to "what DYTM Office would do" (account ownership, position queries, withdraw / repay calldata behaviour); the asset-guard / Ondo / EasySwapperV2 wiring under test is the real production code. When DYTM ships an Ethereum market with GM-supportable collateral, the only change required is swapping the three mock addresses for the deployed ones.
