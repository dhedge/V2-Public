

# Functions:
- [`delegateCollateral(uint128 accountId, uint128 poolId, address collateralType, uint256 amount, uint256 leverage)`](#IVaultModule-delegateCollateral-uint128-uint128-address-uint256-uint256-)
- [`getPositionCollateralRatio(uint128 accountId, uint128 poolId, address collateralType)`](#IVaultModule-getPositionCollateralRatio-uint128-uint128-address-)
- [`getPositionDebt(uint128 accountId, uint128 poolId, address collateralType)`](#IVaultModule-getPositionDebt-uint128-uint128-address-)
- [`getPositionCollateral(uint128 accountId, uint128 poolId, address collateralType)`](#IVaultModule-getPositionCollateral-uint128-uint128-address-)
- [`getPosition(uint128 accountId, uint128 poolId, address collateralType)`](#IVaultModule-getPosition-uint128-uint128-address-)
- [`getVaultDebt(uint128 poolId, address collateralType)`](#IVaultModule-getVaultDebt-uint128-address-)
- [`getVaultCollateral(uint128 poolId, address collateralType)`](#IVaultModule-getVaultCollateral-uint128-address-)
- [`getVaultCollateralRatio(uint128 poolId, address collateralType)`](#IVaultModule-getVaultCollateralRatio-uint128-address-)



# Function `delegateCollateral(uint128 accountId, uint128 poolId, address collateralType, uint256 amount, uint256 leverage)` {#IVaultModule-delegateCollateral-uint128-uint128-address-uint256-uint256-}
Updates an account's delegated collateral amount for the specified pool and collateral type pair.


## Parameters:
- `accountId`: The id of the account associated with the position that will be updated.

- `poolId`: The id of the pool associated with the position.

- `collateralType`: The address of the collateral used in the position.

- `amount`: The new amount of collateral delegated in the position, denominated with 18 decimals of precision.

- `leverage`: The new leverage amount used in the position, denominated with 18 decimals of precision.

Requirements:

- `msg.sender` must be the owner of the account, have the `ADMIN` permission, or have the `DELEGATE` permission.
- If increasing the amount delegated, it must not exceed the available collateral (`getAccountAvailableCollateral`) associated with the account.
- If decreasing the amount delegated, the liquidity position must have a collateralization ratio greater than the target collateralization ratio for the corresponding collateral type.

Emits a {DelegationUpdated} event.



# Function `getPositionCollateralRatio(uint128 accountId, uint128 poolId, address collateralType) → uint256 ratioD18` {#IVaultModule-getPositionCollateralRatio-uint128-uint128-address-}
Returns the collateralization ratio of the specified liquidity position. If debt is negative, this function will return 0.


## Parameters:
- `accountId`: The id of the account whose collateralization ratio is being queried.

- `poolId`: The id of the pool in which the account's position is held.

- `collateralType`: The address of the collateral used in the queried position.


## Return Values:
- ratioD18 The collateralization ratio of the position (collateral / debt), denominated with 18 decimals of precision.


# Function `getPositionDebt(uint128 accountId, uint128 poolId, address collateralType) → int256 debtD18` {#IVaultModule-getPositionDebt-uint128-uint128-address-}
Returns the debt of the specified liquidity position. Credit is expressed as negative debt.


## Parameters:
- `accountId`: The id of the account being queried.

- `poolId`: The id of the pool in which the account's position is held.

- `collateralType`: The address of the collateral used in the queried position.


## Return Values:
- debtD18 The amount of debt held by the position, denominated with 18 decimals of precision.


# Function `getPositionCollateral(uint128 accountId, uint128 poolId, address collateralType) → uint256 collateralAmountD18, uint256 collateralValueD18` {#IVaultModule-getPositionCollateral-uint128-uint128-address-}
Returns the amount and value of the collateral associated with the specified liquidity position.


## Parameters:
- `accountId`: The id of the account being queried.

- `poolId`: The id of the pool in which the account's position is held.

- `collateralType`: The address of the collateral used in the queried position.


## Return Values:
- collateralAmountD18 The amount of collateral used in the position, denominated with 18 decimals of precision.

- collateralValueD18 The value of collateral used in the position, denominated with 18 decimals of precision.


# Function `getPosition(uint128 accountId, uint128 poolId, address collateralType) → uint256 collateralAmountD18, uint256 collateralValueD18, int256 debtD18, uint256 collateralizationRatioD18` {#IVaultModule-getPosition-uint128-uint128-address-}
Returns all information pertaining to a specified liquidity position in the vault module.


## Parameters:
- `accountId`: The id of the account being queried.

- `poolId`: The id of the pool in which the account's position is held.

- `collateralType`: The address of the collateral used in the queried position.


## Return Values:
- collateralAmountD18 The amount of collateral used in the position, denominated with 18 decimals of precision.

- collateralValueD18 The value of the collateral used in the position, denominated with 18 decimals of precision.

- debtD18 The amount of debt held in the position, denominated with 18 decimals of precision.

- collateralizationRatioD18 The collateralization ratio of the position (collateral / debt), denominated with 18 decimals of precision.



# Function `getVaultDebt(uint128 poolId, address collateralType) → int256 debtD18` {#IVaultModule-getVaultDebt-uint128-address-}
Returns the total debt (or credit) that the vault is responsible for. Credit is expressed as negative debt.


## Parameters:
- `poolId`: The id of the pool that owns the vault whose debt is being queried.

- `collateralType`: The address of the collateral of the associated vault.


## Return Values:
- debtD18 The overall debt of the vault, denominated with 18 decimals of precision.



# Function `getVaultCollateral(uint128 poolId, address collateralType) → uint256 collateralAmountD18, uint256 collateralValueD18` {#IVaultModule-getVaultCollateral-uint128-address-}
Returns the amount and value of the collateral held by the vault.


## Parameters:
- `poolId`: The id of the pool that owns the vault whose collateral is being queried.

- `collateralType`: The address of the collateral of the associated vault.


## Return Values:
- collateralAmountD18 The collateral amount of the vault, denominated with 18 decimals of precision.

- collateralValueD18 The collateral value of the vault, denominated with 18 decimals of precision.


# Function `getVaultCollateralRatio(uint128 poolId, address collateralType) → uint256 ratioD18` {#IVaultModule-getVaultCollateralRatio-uint128-address-}
Returns the collateralization ratio of the vault. If debt is negative, this function will return 0.


## Parameters:
- `poolId`: The id of the pool that owns the vault whose collateralization ratio is being queried.

- `collateralType`: The address of the collateral of the associated vault.


## Return Values:
- ratioD18 The collateralization ratio of the vault, denominated with 18 decimals of precision.


