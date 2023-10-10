

# Functions:
- [`txGuard(address, address, bytes)`](#ClosedAssetGuard-txGuard-address-address-bytes-)
- [`getBalance(address, address)`](#ClosedAssetGuard-getBalance-address-address-)
- [`removeAssetCheck(address pool, address asset)`](#ClosedAssetGuard-removeAssetCheck-address-address-)



# Function `txGuard(address, address, bytes) → uint16 txType, bool` {#ClosedAssetGuard-txGuard-address-address-bytes-}
Doesn't allow any transactions uses separate contract guard that should be migrated here



## Return Values:
- txType transaction type described in PoolLogic

- isPublic if the transaction is public or private


# Function `getBalance(address, address) → uint256` {#ClosedAssetGuard-getBalance-address-address-}
Returns the balance of the managed asset



## Return Values:
- balance The asset balance of given pool for the given asset


# Function `removeAssetCheck(address pool, address asset)` {#ClosedAssetGuard-removeAssetCheck-address-address-}
Necessary check for remove asset


## Parameters:
- `pool`: Address of the pool

- `asset`: Address of the remove asset



