# Velodrome V2 LP Withdrawal Slippage Issue

## Problem Overview

Velodrome V2 LP token withdrawals can incorrectly fail slippage checks (error `dh26` at [PoolLogic.sol](../contracts/PoolLogic.sol#L585)) even when there is no actual slippage. This occurs due to an architectural mismatch between how the vault calculates expected withdrawal value versus how it tracks actual withdrawn value.

## Root Cause

The issue stems from a discrepancy in how fees and rewards are handled:

1. **Balance Calculation (Expected Value)**: `VelodromeV2LPAssetGuard.getBalance()` includes:

   - LP tokens held directly in the pool
   - LP tokens staked in the gauge
   - Claimable fees from the LP pair (converted to LP-equivalent value)
   - Claimable rewards from the gauge (converted to LP-equivalent value)

2. **Withdrawal Processing (Actual Value)**: During withdrawal, `VelodromeV2LPAssetGuard.withdrawProcessing()`:

   - Claims fees and transfers them **directly to the user** (not to the pool)
   - Claims rewards and transfers them **directly to the user** (not to the pool)
   - Withdraws LP tokens from the gauge to the pool

3. **Value Tracking Mismatch**: [PoolLogic.sol#L573-L575](../contracts/PoolLogic.sol#L573-L575) only captures tokens that arrive **in the pool contract**:

   ```solidity
   uint256 assetBalanceAfter = IERC20Upgradeable(withdrawAsset).balanceOf(address(this));
   withdrawBalance = withdrawBalance.add(assetBalanceAfter.sub(assetBalanceBefore));
   ```

4. **Slippage Check Failure**: [PoolLogic.sol#L580-L587](../contracts/PoolLogic.sol#L580-L587) compares:

   - `withdrawBalance` (only LP tokens that arrived in pool)
   - vs `expectedWithdrawValue` (includes fees/rewards that went to user)

   When fees/rewards exist, `withdrawBalance < expectedWithdrawValue`, triggering the slippage check to fail with error `dh26`.

## Technical Details

### Code Flow

1. **Expected Value Calculation** ([PoolLogic.sol#L537-L538](../contracts/PoolLogic.sol#L537-L538)):

   ```solidity
   params.portionBalance = IAssetGuard(params.guard).getBalance(address(this), _asset).mul(_portion).div(10 ** 18);
   params.expectedWithdrawValue = _assetValue(_asset, params.portionBalance);
   ```

2. **Fee Transfer** ([VelodromeV2LPAssetGuard.sol#L64-L98](../contracts/guards/assetGuards/velodrome/VelodromeV2LPAssetGuard.sol#L64-L98)):

   - Claims fees from LP pair
   - Transfers fee tokens directly to user if not supported in vault
   - **These tokens bypass the pool contract**

3. **Balance Capture** ([PoolLogic.sol#L564-L575](../contracts/PoolLogic.sol#L564-L575)):

   ```solidity
   uint256 assetBalanceBefore = IERC20Upgradeable(withdrawAsset).balanceOf(address(this));
   for (uint256 i = 0; i < txCount; i++) {
     externalWithdrawProcessed = transactions[i].to.tryAssemblyCall(transactions[i].txData);
   }
   uint256 assetBalanceAfter = IERC20Upgradeable(withdrawAsset).balanceOf(address(this));
   withdrawBalance = withdrawBalance.add(assetBalanceAfter.sub(assetBalanceBefore));
   ```

4. **Slippage Check** ([PoolLogic.sol#L580-L587](../contracts/PoolLogic.sol#L580-L587)):
   ```solidity
   if (params.regularProcessingUsed && _complexAssetData.slippageTolerance != 0 && withdrawAsset != address(0)) {
     require(
       _assetValue(withdrawAsset, withdrawBalance) >=
         params.expectedWithdrawValue.mul(10_000 - _complexAssetData.slippageTolerance).div(10_000),
       "dh26"
     );
   }
   ```

### When This Occurs

#### Scenario 1: Only Claimable Fees (No LP Tokens)

- Position has LP tokens fully staked in gauge
- Claimable fees have accumulated
- No LP tokens in direct pool balance
- **Result**: `withdrawBalance = 0`, but `expectedWithdrawValue > 0` → **REVERTS**

Example from testing (block 145760000):

- Asset: `0x124D69DaeDA338b1b31fFC8e429e39c9A991164e`
- `claimable1`: 598937193347 (worth ~1994 LP tokens)
- `withdrawBalance`: 0 (fees went to user)
- `expectedWithdrawValue`: 1994
- Slippage check: `0 < 1994 * 0.95` → **REVERT "dh26"**

#### Scenario 2: LP Tokens + Claimable Fees

- Position has LP tokens in gauge
- Some claimable fees/rewards exist
- **Result**: May pass or fail depending on fee amount relative to slippage tolerance

Example from testing (block 146104698):

- Asset: `0xbC26519f936A90E78fe2C9aA2A03CC208f041234`
- Gauge LP balance: 132574905
- Claimable fees: 0
- `gauge.withdraw()` brings LP tokens to pool
- `withdrawBalance`: 1715650985 (captured via line 575)
- Slippage check: **PASSES**

#### Scenario 3: High Fees Relative to Slippage

- Position has LP tokens
- Fees/rewards are significant (e.g., 10% of position value)
- Slippage tolerance is low (e.g., 5%)
- **Result**: `withdrawBalance` (LP only) might still be < `expectedWithdrawValue * (1 - slippage)` → **REVERTS**

### Why Fees Go Directly to User

From [VelodromeV2LPAssetGuard.sol#L64-L98](../contracts/guards/assetGuards/velodrome/VelodromeV2LPAssetGuard.sol#L64-L98):

```solidity
// If fee tokens are not supported in the vault, transfer them directly to user
if (claimable0 > 0 && !IPoolManagerLogic(pool).isSupportedAsset(token0)) {
  withdrawTxs[txCount++] = MultiTransaction({
    to: token0,
    txData: abi.encodeWithSelector(IERC20.transfer.selector, to, claimable0)
  });
}
```

This design is intentional - fee tokens might not be supported assets in the vault, so they must be sent directly to the user rather than being held in the pool.

## Workaround Solution

### Client-Side Implementation

Pass `slippageTolerance = 0` for Velodrome V2 LP assets when calling withdrawal functions:

```typescript
// Detect Velodrome V2 LP assets
const isVelodromeV2LP = assetGuard === VELODROME_V2_LP_ASSET_GUARD;

const complexAssetsData = supportedAssets.map((asset) => ({
  supportedAsset: asset.address,
  withdrawData: "0x",
  slippageTolerance: isVelodromeV2LP ? 0 : defaultSlippage, // e.g., 100 = 1%
}));

await pool.withdrawSafe(fundTokenAmount, complexAssetsData);
```

### How It Works

The slippage check at [PoolLogic.sol#L580](../contracts/PoolLogic.sol#L580) has this condition:

```solidity
if (params.regularProcessingUsed && _complexAssetData.slippageTolerance != 0 && withdrawAsset != address(0))
```

When `slippageTolerance == 0`, the **entire slippage check is skipped**, preventing the false positive revert.

## Testing Evidence

Test file: [WithdrawRevertTest.t.sol](../test/integration/ovm/velodromeV2/WithdrawRevertTest.t.sol)

### Block 145760000 - Reverts

```solidity
Asset: 0x124D69DaeDA338b1b31fFC8e429e39c9A991164e
claimable0: 0
claimable1: 598937193347
getBalance(): 1994 (from fees)
withdrawBalance: 0 (fees transferred to user)
Slippage check: 0 < 1994 * 0.95 → REVERT "dh26"
```

### Block 146104698 - Succeeds

```solidity
Asset: 0x124D69DaeDA338b1b31fFC8e429e39c9A991164e
claimable0: 0
claimable1: 0
earned: 0
getBalance(): 0
withdrawBalance: 0
Slippage check: 0 >= 0 → PASS
```

## Recommendations

1. **Long-term**: Consider architectural refactor to support multi-asset withdrawals or external transfer tracking

## Related Files

- [PoolLogic.sol](../contracts/PoolLogic.sol) - Main withdrawal logic with slippage check
- [VelodromeV2LPAssetGuard.sol](../contracts/guards/assetGuards/velodrome/VelodromeV2LPAssetGuard.sol) - Asset guard handling fee transfers
- [WithdrawRevertTest.t.sol](../test/integration/ovm/velodromeV2/WithdrawRevertTest.t.sol) - Test cases demonstrating the issue
