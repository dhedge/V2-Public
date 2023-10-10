

# Functions:
- [`constructor(address _usdc, address _aaveLendingPoolV3)`](#MaiVaultAssetGuard-constructor-address-address-)
- [`getBalance(address pool, address asset)`](#MaiVaultAssetGuard-getBalance-address-address-)
- [`getDecimals(address)`](#MaiVaultAssetGuard-getDecimals-address-)



# Function `constructor(address _usdc, address _aaveLendingPoolV3)` {#MaiVaultAssetGuard-constructor-address-address-}
No description




# Function `getBalance(address pool, address asset) → uint256 balance` {#MaiVaultAssetGuard-getBalance-address-address-}
Returns the USD value of all the pools vaults


## Parameters:
- `pool`: address of the pool

- `asset`: address of the maiVault


## Return Values:
- balance The asset balance of given pool


# Function `getDecimals(address) → uint256 decimals` {#MaiVaultAssetGuard-getDecimals-address-}
Returns decimal of USD value





