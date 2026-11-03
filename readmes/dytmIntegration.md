# DYTM Integration

DYTM is an external lending protocol integrated into dHEDGE as **asset type 106**. Pools interact with the DYTM Office contract to supply collateral, borrow assets, and manage leveraged positions.

The integration consists of four main pieces:

1. **Contract Guard** (`DytmOfficeContractGuard`) — validates all pool transactions to DYTM Office
2. **Asset Guard** (`DytmOfficeAssetGuard`) — handles balance calculation, withdrawal account splitting, and the frontend planning helper
3. **Withdraw Processor** (`DytmWithdrawProcessor`) — a shared singleton that runs the unwind action plan in an isolated context
4. **EasySwapperV2 Withdrawal Library** (`DytmWithdrawLib`) — invoked from the `WithdrawalVault`, hands the split DYTM accounts to the processor and enforces the economic post-checks

---

## 1. Contract Guard

`DytmOfficeContractGuard` implements `ITxTrackingGuard` for two-phase validation (pre-tx and post-tx).

### Guarded Transaction Types

| Tx Type          | ID  | Method                         | Validation                                                                  |
| ---------------- | --- | ------------------------------ | --------------------------------------------------------------------------- |
| Supply           | 118 | `IDytmOffice.supply`           | Account ownership, market whitelist, asset support                          |
| Withdraw         | 119 | `IDytmOffice.withdraw`         | Account ownership, market whitelist, receiver == pool                       |
| Borrow           | 120 | `IDytmOffice.borrow`           | Account ownership, market whitelist, receiver == pool, no mixed debt assets |
| Repay            | 121 | `IDytmOffice.repay`            | Account ownership, market whitelist                                         |
| SwitchCollateral | 123 | `IDytmOffice.switchCollateral` | Account ownership, market whitelist, asset support                          |
| DelegationCall   | 122 | `IDytmOffice.delegationCall`   | Delegatee == poolLogic (pool is its own delegatee)                          |

### Two-Phase Validation

**`txGuard()` (pre-tx):**

- Verifies pool is whitelisted and DYTM Office is a supported asset
- Decodes parameters, validates account ownership, market whitelist, asset support
- For delegation calls: sets `isOngoingDelegationCall` flag, prevents nesting

**`afterTxGuard()` (post-tx):**

- Enforces health factor >= 1.01e18 for borrow/withdraw via `IDytmPeriphery.getAccountPosition()`
- Tracks active market IDs in NFT tracker (`DhedgeNftTrackerStorage`)
- Cleans up inactive markets (zero collateral + healthy)

### Delegation Call Deferred Validation

During a delegation call, the pool executes multiple operations (supply, borrow, etc.) as a batch. Individual health factor checks and market tracking are **deferred** — queued via `DytmDelegationCallCheckGuard` and executed once at the end of the delegation call in `afterTxGuard`.

### Whitelisting

Two levels:

- **Pool whitelist**: `poolsWhitelist[poolLogic]` — which pools can use DYTM
- **Market whitelist**: `dytmMarketsWhitelist[marketId]` — which DYTM markets are allowed

Both are set in the constructor via `VaultSetting[]` and `DytmMarketSetting[]`.

### Active Market Tracking

Uses `DhedgeNftTrackerStorage` with NFT type `keccak256("DYTM_MARKET_ID_TYPE")` to track which markets a pool has positions in. Markets are added on supply and removed when collateral reaches zero.

---

## 2. Asset Guard

`DytmOfficeAssetGuard` extends `ClosedAssetGuard`, `DytmSplitTokenIdTracker`, and `DytmWithdrawalCalculator`.

### Balance Calculation

`getBalance(pool, asset)` iterates all tracked market IDs and sums `totalCollateralValueUSD - debtValueUSD` for each **healthy** position. Returns USD value with 18 decimals.

### Withdrawal Processing (Account Splitting)

When a pool investor withdraws, `withdrawProcessing()` is called by PoolLogic. It splits each DYTM position proportionally:

```
For each active market position (healthy + has collateral):
  1. delegationCall to AccountSplitterAndMerger.SPLIT_ACCOUNT
     -> creates an isolated account with (portion) of assets & debts
  2. IDytmOffice.transfer -> transfers the isolated account to the withdrawer (WithdrawalVault)
```

Two overloads exist:

- **4-param** (`IAssetGuard`): called when `ComplexAsset.withdrawData` is empty (no-debt case)
- **5-param** (`IComplexAssetGuard`): called when `withdrawData` is non-empty (has-debt case with swap data)

Both delegate to `_withdrawProcessingInternal()`.

Split positions are tracked in `DytmSplitTokenIdTracker` keyed by recipient address (the WithdrawalVault). They are later retrieved by `DytmWithdrawLib` during `unrollAssets`.

The processor address the unwind hands off to is read from `DytmOfficeAssetGuard.dytmWithdrawProcessor()` — an immutable set in the asset guard constructor (see section 5).

### Frontend Planning Helper (callStatic)

**`DytmWithdrawalCalculator.previewWithdrawal(pool, poolTokenAmount)`** — single entrypoint, guarded with `cannotExecute` (inherited from `AutomationBase`: requires `tx.origin == address(0)` or the Chainlink DON simulation sentinel `0x1111...1111`), so it only runs inside an `eth_call` simulation and is not part of the on-chain runtime path. Returns `DytmParamStructs.AssetData[]` — a flat list with one entry per collateral and one per non-zero debt across every withdrawable DYTM market.

```solidity
struct AssetData {
  address asset; // raw DYTM-held asset (vault token, ERC20, GM, PT, ...)
  uint256 amount; // portion-scaled `assets` value
  uint16 assetType; // factory asset type (0=ERC20, 4=lending, 37=PT, 41=GM, ...)
  bool isPool; // true = dHEDGE vault token (factory.isPool(asset))
  bool isDebt; // true = DYTM debt slot; false = DYTM collateral slot
  uint88 marketId; // DYTM market this entry belongs to
  uint256 accountId; // split account ID, already shifted by 160 bits
  uint256 tokenId; // collateral tokenId for WithdrawParams; 0 when isDebt
  uint248 debtKey; // debt key for RepayParams; 0 when !isDebt
  uint256 shares; // portion-scaled shares for Withdraw/Repay params
}
```

The frontend uses each entry's classification fields (`assetType`, `isPool`, `isDebt`) to dispatch the right off-chain action:

- `assetType == 41` (Ondo GM) → fetch a signed Ondo attestation sized to `amount`.
- `assetType == 37` (Pendle PT) → fetch Pendle redeem calldata.
- `isPool == true` (dHEDGE vault collateral) → withdraw the vault token after the DYTM unwind and plan swaps for its underlyings client-side (no on-chain flattening).
- Otherwise → DEX aggregator swap.

The action-construction fields (`accountId`, `marketId`, `tokenId` / `debtKey`, `shares`) drop straight into `DytmParamStructs.WithdrawParams` / `RepayParams`. Multiple entries from the same market share the same `accountId`. Unhealthy / zero-collateral markets are skipped, matching the on-chain split path in `DytmOfficeAssetGuard.withdrawProcessing`.

Plain Ondo GM holdings (outside DYTM) plan via `OndoGMTokenAssetGuard.previewGmTokenAmount(pool, asset, poolTokenAmount)`, called by the frontend with `callStatic`. It is state-mutating (it mints the manager fee for an accurate `totalSupply`), guarded with `cannotExecute`, and computes `portionAmount = balance × portion / 1e18` shaved by 1 bps — the same `portionAmount` `OndoGMTokenAssetGuard.withdrawProcessing` checks `quote.quantity` against. If that portion is worth less than the configured `minRedeemValue` (including a zero balance), it returns `0` to signal the frontend that no Ondo attestation is needed — mirroring the 4-arg `withdrawProcessing` dust guard.

---

## 3. Withdraw Processor

`DytmWithdrawProcessor` is a **shared singleton** (one deployment per chain, not one per pool/vault). The `WithdrawalVault` transfers the freshly-split DYTM accounts to it, then calls `process()`. The processor — not the vault — is the DYTM `delegationCall` delegatee, so the unwind action plan executes in the **processor's** context.

### `process(UnwindPlanRequest)`

```solidity
struct UnwindPlanRequest {
  address dytmOffice;
  address pool; // where a bounded dust remnant is handed back (see Settlement Model)
  DytmSplitTokenIdTracker.SplitPosition[] splitPositions;
  DytmWithdrawLib.Action[] actions;
  address outputAsset; // locked to usdc() by DytmWithdrawLib
}
```

Steps:

1. **Caller auth** — `_isAuthorizedVault(msg.sender)`. The caller must be a `WithdrawalVault` registered against its claimed `depositor()` in `easySwapperV2` (`withdrawalContracts` or `limitOrderContracts`). A malicious contract can spoof `depositor()`, but the registry lookup only matches a vault `easySwapperV2` itself deployed.
2. **Zero the settlement asset** — any `usdc` an earlier unwind left here goes to `pool` before this one is measured, so the plan starts from zero and is neither credited with nor able to reach someone else's leftover. The processor settles in its immutable `usdc`, not in `params.outputAsset`; `DytmWithdrawLib` requires the two to be equal for its own vault-side accounting, and reading the immutable keeps this contract's sweep and measurement provably the same token.
3. **`IDytmOffice.delegationCall(delegatee = processor)`** → runs `onDelegationCallback`.
4. **Drained / remnant post-check** (per split account) — see Settlement Model.
5. **Forward** the whole `usdc` balance back to the calling vault.

`params.pool` is not validated here, and a `PoolFactory.isPool` check would add nothing — anyone can create a dHEDGE pool, so it would not narrow the destination if the address were caller-chosen. What constrains it is the flow: `EasySwapperV2._initWithdrawalFor` requires a factory pool and hands the same address to `withdrawDhedgeVault` and `unrollAssets` in one call, so `pool` is the vault whose `withdrawProcessing` created the split positions being unwound. With no split positions `DytmWithdrawLib` returns before calling `process` at all, and the nested-vault recursion can't reach the DYTM branch (it passes an empty `ComplexAsset[]`, which reverts with `missing DYTM complex asset data`).

### `onDelegationCallback`

Three passes:

1. **Validate + empty.** Every action goes through `_checkAction`. For each token the plan approves, the processor's whole balance of that token is transferred to `pool` first.
2. **Execute.** The `actions[]` run as a flat multicall inside DYTM's delegation context.
3. **Settle.** Every allowance the plan granted is zeroed, and whatever the plan produced and did not consume goes to `pool`.

`_checkAction` classifies each action:

- **Self-call** (`action.to == processor`) → reverts.
- **`transfer` / `transferFrom`** → reverts. Supported unwinds use approve + the router/aggregator's own `transferFrom`, never a direct push from the processor.
- **`approve` / `increaseAllowance`** → the spender is recorded so the allowance is reset to 0 after the multicall completes, and the token is emptied in pass 1.

**Why pass 1 exists.** The processor is shared, and a plan is arbitrary user-supplied calldata running with its authority. `_checkAction` stops the plan from moving the processor's tokens _itself_, but not from approving an arbitrary spender (canonical Permit2, Multicall3, …) and then calling that spender — those selectors are not the blocked ones, and the allowance cleanup runs afterwards. Emptying every approvable token up front is what makes the shared processor behave like a per-withdrawal one: when the first action runs, the only balances present are the ones this plan brought in.

Passes 1 and 3 are both load-bearing, and `DytmLiveVaultWithdrawalTestEthereum` pins each:

- Without pass 1, `test_revert_plan_cannot_sweep_processor_leftover` fails — the plan sweeps the leftover. Pass 3 cannot substitute: it only cleans tokens _that_ plan approved, so a plan that strands a token it never approved leaves it for the next plan to take.
- Without pass 3, the four live-vault withdrawals fail on `vault must receive the leftover` — the GM slice sits in the processor until some later plan approves that token, and then goes to _that_ plan's pool.

`test_deployed_processor_lets_the_same_plan_sweep_the_leftover` pins the live behaviour this replaces.

Two consequences worth knowing:

- A leftover of a token the plan **does** approve is handed to `pool` — including one an unrelated vault's unwind left behind. For a token the receiving pool doesn't support, that value becomes untracked pool balance rather than something `rescueToken` can recover, so clear legacy leftovers before deploying.
- A leftover of a token the plan **doesn't** approve is untouched and stays `rescueToken`'s job.

### `rescueToken` (onlyOwner)

Recovers leftovers of tokens no plan has approved. Drained DYTM account NFTs that pile up here are inert (no collateral, no debt) and need no dedicated rescue path.

---

## 4. EasySwapperV2 Withdrawal Flow

### End-to-End Flow

```
EasySwapperV2.initWithdrawal(pool, amount, complexAssetsData)
  |
  |-- Creates WithdrawalVault for investor (if not exists)
  |-- WithdrawalVault.withdrawDhedgeVault()
  |     |-- PoolLogic.withdrawToSafe(vault, ...)
  |           |-- For DYTM (asset type 106):
  |           |     DytmOfficeAssetGuard.withdrawProcessing()
  |           |       -> splits accounts proportionally
  |           |       -> transfers isolated accounts to WithdrawalVault
  |           |       -> tracks split positions in DytmSplitTokenIdTracker
  |
  |-- WithdrawalVault.unrollAssets(pool, complexAssetsData)
        |-- For DYTM (asset type 106):
              DytmWithdrawLib.processDytmPosition()   (runs in vault context)
                |-- Reads split positions from tracker (keyed by vault address)
                |-- Decodes ComplexAsset.withdrawData as DytmWithdrawLib.UnwindPlan
                |-- Locks plan.outputAsset == processor.usdc()
                |-- Caps complexAsset.slippageTolerance <= 2% (MAX_SLIPPAGE_TOLERANCE_BPS)
                |-- Snapshots vault's outputAsset balance + the split positions' net USD value
                |-- Transfers the split accounts to DytmWithdrawProcessor
                |-- DytmWithdrawProcessor.process(UnwindPlanRequest)
                |     |-- Requires pool is a dHEDGE pool + outputAsset == usdc
                |     |-- Sweeps any stale outputAsset to the pool, so this unwind starts at zero
                |     |-- IDytmOffice.delegationCall(delegatee = processor)
                |     |     |-- DytmWithdrawProcessor.onDelegationCallback
                |     |           |-- Pass 1: _checkAction each action; empty every approved token
                |     |             to the pool
                |     |           |-- Pass 2: executes UnwindPlan.actions[] as a flat multicall
                |     |             (frontend-built calldata)
                |     |           |-- Pass 3: zeroes allowances; hands the pool what the plan
                |     |             produced and did not consume
                |     |-- Per-account post-check: fully drained, or a bounded dust remnant
                |     |     handed back to the pool (see Settlement Model)
                |     |-- Forwards the outputAsset gain back to the vault
                |-- Remnant bound: sum of leftover collateral USD across split accounts <= $3
                |-- Slippage check: received >= minOutputAmount AND
                |     received >= expectedOutput * (1 - slippageTolerance)
                |     (expectedOutput derived from DYTM Periphery USD valuation via asset handler)
                |-- tokensToTrack = [outputAsset]   (= usdc)
```

### Settlement Model

The runtime path is a generic multicall executor — there are no on-chain branches on "debt vs. no debt" or "swap vs. no swap." The frontend assembles whatever sequence of DYTM actions (`withdraw`, `repay`, `switchCollateral`, …) and external calls (e.g. Ondo `swapExactInWithAttestation`, Pendle PT redemption, Odos swap) the unwind needs, and submits it as `UnwindPlan.actions[]`. Safety comes from these on-chain post-checks:

1. **Output asset locked to USDC** — `DytmWithdrawLib` requires `plan.outputAsset == DytmWithdrawProcessor.usdc()`. This keeps the slippage cap denominated in USD, prevents non-DEX-tradeable outputs (PT, dHEDGE pool tokens) from being handed to the user, and removes the GM-output edge case that would denominate the cap in mint units.

2. **Drained-or-bounded-remnant** — every split account transferred to the processor must end the delegation call either:
   - fully drained (zero collateral IDs **and** zero debt ID in its market), in which case the inert account stays in the processor; or
   - holding a small remnant (e.g. a sub-\$1 GM leg that Ondo can't attest a swap for), in which case the processor `transfer`s the account back to the **pool** so its value isn't orphaned in the shared processor. The pool's manager can later merge it into the pool's own account.

   `DytmWithdrawLib` then bounds the total leftover collateral across all split accounts to `MAX_REMNANT_VALUE_USD` (\$3) — so a plan can't lazily orphan meaningful value. The leftover debt is bounded indirectly: to leave debt the account must stay solvent through the withdraw actions, so `collateral >= debt / maxLTV`, and the \$3 collateral cap transitively bounds the debt to dust.

   This cap covers collateral left **inside** a split account. Loose ERC20 the plan drained out of the account but did not sell — the live frontend drains with `shares: type(uint256).max` while the signed Ondo quote is sized to the preview's `mismatchDeltaNumerator`-buffered amount, so ~5 bps of every GM leg ends up loose — is covered instead by pass 3 of `onDelegationCallback`, which hands it to the pool.

3. **Two-gate slippage check** — `received` (`outputAsset` balance gain across the whole `process` call) must satisfy **both**:
   - `received >= UnwindPlan.minOutputAmount` (frontend-supplied absolute floor), and
   - `received >= expectedOutput * (1 - slippageTolerance)`, where `expectedOutput` is the split positions' **net USD value** (`Σ max(0, collateralUSD − debtUSD)` from DYTM Periphery) converted to `outputAsset` units via the dHEDGE asset handler, and `slippageTolerance` is the per-withdrawal value capped at 2%.

   This USD-denominated relative gate — not `minOutputAmount` alone — is the primary economic protection against an opaque action plan under-delivering.

4. **Atomicity** — any revert inside `actions[]`, the drained/remnant post-check, the remnant bound, or the slippage check rolls back the whole withdrawal. The remnant transfer to the pool only persists if every later check passes.

### ComplexAsset Data Encoding

```solidity
ComplexAsset({
    supportedAsset: dytmOffice,
    withdrawData: abi.encode(DytmWithdrawLib.UnwindPlan({
        actions: [
            // flat list of (address to, bytes data) calls executed by the processor
            // inside DYTM's delegationCall. Typically:
            //   1. IDytmOffice.withdraw(...)          for each collateral
            //   2. extras unwind (e.g. Ondo swapExactInWithAttestation,
            //      Pendle PT redemption, Odos swap)
            //   3. IDytmOffice.repay(...)             for each debt
        ],
        outputAsset: usdc,            // MUST equal DytmWithdrawProcessor.usdc()
        minOutputAmount: 100_000_000  // frontend-computed absolute floor
    })),
    slippageTolerance: 100             // 1% — load-bearing here; capped at 2% on-chain
})
```

The frontend builds `actions[]` by:

1. Calling `previewWithdrawal(pool, amount)` once to get the flat `AssetData[]` covering all withdrawable collaterals and debts (with their `accountId`, `marketId`, `tokenId` / `debtKey`, and `shares` already populated).
2. For each `AssetData` entry, dispatching the right off-chain action based on its classification flags — fetching signed attestations for Ondo GM slots, Pendle redeem calldata for PT slots, DEX aggregator quotes otherwise; for `isPool == true` vault collaterals, planning the vault-token withdrawal and recursively planning its underlyings.
3. Stitching the per-market `withdraw` / off-chain-unwind / `repay` calls into a single flat list using the action-construction fields directly. The final swaps must produce `usdc` (the locked `outputAsset`).

The on-chain dispatcher does not parse the action shapes — it just executes them in order, subject to the `_checkAction` filter.

---

## 5. Deployment & Configuration

### Contract Guard config (`DytmConfig`)

```solidity
struct DytmConfig {
  address dytmOffice; // DYTM Office contract
  address dytmPeriphery; // Read-only position queries
  address dhedgePoolFactory; // dHEDGE pool factory
  address nftTracker; // DhedgeNftTrackerStorage for market tracking
  uint256 maxDytmMarkets; // Max active markets per pool
}
```

Set in the `DytmOfficeContractGuard` constructor (immutable). Changing any value requires redeploying the guard.

### Asset Guard constructor

`DytmOfficeAssetGuard` is deployed with (all immutable):

```
(mismatchDeltaNumerator, dytmOffice, poolFactory, dytmPeriphery, accountSplitterAndMerger, dytmWithdrawProcessor)
```

`accountSplitterAndMerger` (for withdrawal splitting) and `dytmWithdrawProcessor` (the unwind processor) live here, not in the contract guard's `DytmConfig`. Because the asset guard stores `dytmWithdrawProcessor` as an immutable, **re-deploying the processor requires re-deploying `DytmOfficeAssetGuard`** and re-registering it via `Governance.setAssetGuard(106, newGuard)`.

### Withdraw Processor constructor

`DytmWithdrawProcessor` is deployed with `(easySwapperV2, dHedgePoolFactory, usdc)` (all immutable). `usdc` is the canonical settlement token every unwind is locked to.

### Whitelist Requirements

For a pool to use DYTM:

1. Pool must be in `poolsWhitelist` (set in contract guard constructor)
2. Market IDs must be in `dytmMarketsWhitelist` (set in contract guard constructor)
3. DYTM Office must be a supported asset (type 106) in the pool

For EasySwapperV2 withdrawal of a leverage vault (pool that uses another dHEDGE token as DYTM collateral):

4. The leverage vault's `WithdrawalVault` must be whitelisted in `dhedgePoolFactory.receiverWhitelist`
