# Flat Money Points

This document will describe the integration for the flatcoin Flat Money Points (`FMP`) asset.

The points when minted are subject to a 1 year linear lockup.
Unlocking Points before the 1 year expiry, means that the user pays a tax to the treasury and only gets a portion of their unlocked Points.
The remainder goes to the Flat Money treasury.

The Points integration is only for the asset (no contract guard).
Separately we can integrate the Flatcoin protocol with contract guard.


## Resources

Most of the information for this integration is contained in the Flatcoin repo:

- https://github.com/dhedge/flatcoin-v1

## AssetGuard

### _assetValue

The USD price of the FMP can be based on a TWAP LP oracle that we select and provide liquidity for (eg Aerodrome).

### getBalance

The USD value of the vault's Points can be calculated as follows:

- Get `balanceOf(vault)` - balance of points in vault
- Get `lockedBalance(vault)` - amount of locked points in vault
- Get `getUnlockTax(vault)` - the tax on locked points (starts at 100% 1e18 -> 0)

```
Value of points in the vault =
withdrawableBalance = balance + (lockedBalance * unlockTax / 1e18)
withdrawableValue = withdrawableBalance * FMP price USD
```
### withdrawProcessing

The withdraw processing should unlock the user's portion of the FMP:

- Unlock the user's portion (unlock tax may be charged)
- Send the unlocked tokens to the user's account
