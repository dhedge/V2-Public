# DYTM Integration

DYTM is an external lending protocol integrated into dHEDGE as **asset type 106**. Pools interact with the DYTM Office contract to supply collateral, borrow assets, and manage leveraged positions.

The integration consists of three main pieces:

1. **Contract Guard** (`DytmOfficeContractGuard`) — validates all pool transactions to DYTM Office
2. **Asset Guard** (`DytmOfficeAssetGuard`) — handles balance calculation, withdrawal account splitting, and swap data calculation
3. **EasySwapperV2 Withdrawal Processing** (`DytmWithdrawProcessor` + `DytmWithdrawLib`) — unwinds DYTM positions during investor withdrawals

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

`DytmOfficeAssetGuard` extends `ClosedAssetGuard`, `DytmSplitTokenIdTracker`, and `DytmSwapDataCalculator`.

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

### Swap Data Calculation (Frontend)

`DytmSwapDataCalculator.calculateSwapDataParams()` is called via `callStatic` by the frontend to get swap instructions before initiating withdrawal:

1. Calculates pool portion: `(withdrawAmount - exitFee) / totalSupply`
2. For each market position:
   - Accrues interest on all reserves
   - Flattens collaterals to underlying ERC20s (dHEDGE vaults resolved, Pendle PTs converted)
   - Scales amounts by portion
3. If has debt: filters debt asset from sources, calculates `minDstAmount` with slippage
4. Applies 0.01% mismatch delta reduction to account for management fee drift between calculation and execution

Returns `SwapDataParams { srcData[], dstData }` — the frontend uses this to fetch Odos swap data.

---

## 3. EasySwapperV2 Withdrawal Flow

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
  |-- WithdrawalVault.unrollAssets(pool, investor, complexAssetsData)
        |-- For DYTM (asset type 106):
              DytmWithdrawLib.processDytmPosition()
                |-- Retrieves split positions from tracker (keyed by vault address)
                |-- Finds ComplexAsset entry (slippageTolerance + withdrawData)
                |-- Gets DytmWithdrawProcessor from contract guard
                |-- Transfers isolated accounts from vault to processor
                |-- IDytmOffice.delegationCall -> processor.onDelegationCallback()
                      |
                      |-- Step 1: Decode & validate (asset, vault identity)
                      |-- Step 2: Query positions (accrue interest, get fresh data)
                      |-- Step 3: Resolve collateral swap data (flatten, deduplicate)
                      |-- Step 4: Withdraw collaterals + flatten dHEDGE vaults + unroll PTs
                      |-- Step 5: Settle (branch on debt)
                      |-- Step 6: Return tokensToTrack
```

### No-Debt Settlement

When positions have no debt (`dstData.asset == address(0)`):

1. Transfer all flattened asset amounts to the vault
2. Slippage check: `totalAssetValue >= positionValue * (1 - slippageTolerance)`
3. Return all source asset addresses as `tokensToTrack`

### Has-Debt Settlement (with swap)

When positions have debt and collateral includes non-debt assets (requires `ComplexAsset.withdrawData` with encoded swap data):

1. Validate offchain swap data against current state (src amounts within mismatch delta, dst amount within delta)
2. Swap collaterals to debt asset via Swapper (Odos)
3. Repay all position debts (uses `assets: type(uint256).max` to avoid unpaid debt share dust)
4. Transfer net debt asset gained (balance diff from before withdrawals) to vault
5. Slippage check: `debtAssetGainedValue >= positionValue * (1 - slippageTolerance)`
6. Return debt asset address as `tokensToTrack`

### Has-Debt Settlement (no swap needed)

When positions have debt but all collateral is already the debt asset (`srcData` is empty):

1. Repay all position debts
2. Transfer net debt asset gained (balance diff) to vault
3. Slippage check: `debtAssetGainedValue >= positionValue * (1 - slippageTolerance)`
4. Return debt asset address as `tokensToTrack`

### ComplexAsset Data Encoding

For **no-debt** withdrawal:

```solidity
ComplexAsset({
    supportedAsset: dytmOffice,
    withdrawData: "",              // empty
    slippageTolerance: 100         // 1%
})
```

For **has-debt** withdrawal:

```solidity
ComplexAsset({
    supportedAsset: dytmOffice,
    withdrawData: abi.encode(ComplexAssetSwapData({
        srcData: abi.encode(srcTokenSwapDetails),   // ISwapper.SrcTokenSwapDetails[]
        destData: ISwapper.DestData({destToken, minDestAmount}),
        slippageTolerance: 100
    })),
    slippageTolerance: 100
})
```

The frontend calls `calculateSwapDataParams()` first to get the expected amounts, fetches Odos swap data, then encodes it into `ComplexAssetSwapData`.

---

## 4. Deployment & Configuration

### DytmConfig

```solidity
struct DytmConfig {
  address dytmOffice; // DYTM Office contract
  address dytmPeriphery; // Read-only position queries
  address dhedgePoolFactory; // dHEDGE pool factory
  address nftTracker; // DhedgeNftTrackerStorage for market tracking
  uint256 maxDytmMarkets; // Max active markets per pool
  address accountSplitterAndMerger; // For withdrawal account splitting
  address dytmWithdrawProcessor; // For EasySwapperV2 withdrawal processing
}
```

All fields are **immutable** (set in `DytmOfficeContractGuard` constructor). Changing any value requires redeploying the guard.

### Whitelist Requirements

For a pool to use DYTM:

1. Pool must be in `poolsWhitelist` (set in contract guard constructor)
2. Market IDs must be in `dytmMarketsWhitelist` (set in contract guard constructor)
3. DYTM Office must be a supported asset (type 106) in the pool

For EasySwapperV2 withdrawal of a leverage vault (pool that uses another dHEDGE token as DYTM collateral): 4. The leverage vault's `WithdrawalVault` must be whitelisted in `dhedgePoolFactory.receiverWhitelist`
