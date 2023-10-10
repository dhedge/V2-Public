# Mai.Finance

## Notes:

- Each VaultWrapper will be its own individual asset i.e Optimism MAI Vault (OPMVT)
- A user can have Multiple Vaults per VaultWrapper and it issues ERC721 Tokens and we will need to use NFTStorage. Managers shouldn't really need to have more than one vault per type of underlying.
- We will need to flash borrow mai or some other token and swap to mai to pay down debt during withdrawProcessing.
- Users will not be able to transfer vault erc721 positions.


## Functions

- createVault()
- depositCollateral(uint256 vaultID, uint256 amount)
- borrowToken(uint256 vaultID, uint256 amount)
- withdrawCollateral(uint256 vaultID, uint256 amount)
- payBackToken(uint256 vaultID, uint256 amount)
- approve vault for mai
- withdrawCollateral(uint256 vaultID, uint256 amount)

- burn(vaultId) - burns the erc721
- checkLiquidation(vaultId) - tells you if the vault can be liquidated
- liquidateVault(vaultId) - can only be called if checkLiquidation is true
- collateral(): Address - returns the address of VaultWrappers underlying
- vaultCollateral(vaultID) - gives the vault
- vaultDebt(vaultId) - gives the vault debt in mai
- closingFee() - the amount mai charges for paying back debt (more notes on this in withdrawProcessing) - The Unit of this is 10000 and is hardcoded unfortunately (there is no getter)


# Asset Guard

getBalance(): returns usd value - gets position/s from nftManager and aggregates -> (vaultCollateral * collateralPrice) - (vaultDebt * maiPrice) -

withdrawProcessing() - User receives USDC.

1. Gets Vault Positions from NftStorage
2. For each position
	a. Borrows USDC
	b. Swaps to Mai
	c. PayBackToken debt portion
	d. withdrawCollateral portion
	e. Swaps collateral for USDC
	f. Pays back USDC debt
	g. Transfers remaining USDC to withdrawer

The during PayBack process Mai charges a closingFee which is subtracted from the collateral. The withdrawers collateral amount is adjusted for this fee.

In the case where a Vaults checkLiquidation() status returns true, we cannot simply liquidate vault. MAI liquidation process does not work like that https://docs.mai.finance/liquidation. As per the docs - "liquidators repay 50% of the vault’s debt and withdraw a portion of the locked collateral tokens as compensation". We rely on liquidators in this case.
