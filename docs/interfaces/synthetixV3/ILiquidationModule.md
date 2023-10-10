

# Functions:
- [`liquidate(uint128 accountId, uint128 poolId, address collateralType, uint128 liquidateAsAccountId)`](#ILiquidationModule-liquidate-uint128-uint128-address-uint128-)
- [`liquidateVault(uint128 poolId, address collateralType, uint128 liquidateAsAccountId, uint256 maxUsd)`](#ILiquidationModule-liquidateVault-uint128-address-uint128-uint256-)
- [`isPositionLiquidatable(uint128 accountId, uint128 poolId, address collateralType)`](#ILiquidationModule-isPositionLiquidatable-uint128-uint128-address-)
- [`isVaultLiquidatable(uint128 poolId, address collateralType)`](#ILiquidationModule-isVaultLiquidatable-uint128-address-)

# Events:
- [`Liquidation(uint128 accountId, uint128 poolId, address collateralType, struct ILiquidationModule.LiquidationData liquidationData, uint128 liquidateAsAccountId, address sender)`](#ILiquidationModule-Liquidation-uint128-uint128-address-struct-ILiquidationModule-LiquidationData-uint128-address-)
- [`VaultLiquidation(uint128 poolId, address collateralType, struct ILiquidationModule.LiquidationData liquidationData, uint128 liquidateAsAccountId, address sender)`](#ILiquidationModule-VaultLiquidation-uint128-address-struct-ILiquidationModule-LiquidationData-uint128-address-)


# Function `liquidate(uint128 accountId, uint128 poolId, address collateralType, uint128 liquidateAsAccountId) → struct ILiquidationModule.LiquidationData liquidationData` {#ILiquidationModule-liquidate-uint128-uint128-address-uint128-}
Liquidates a position by distributing its debt and collateral among other positions in its vault.


## Parameters:
- `accountId`: The id of the account whose position is to be liquidated.

- `poolId`: The id of the pool which holds the position that is to be liquidated.

- `collateralType`: The address of the collateral being used in the position that is to be liquidated.

- `liquidateAsAccountId`: Account id that will receive the rewards from the liquidation.


## Return Values:
- liquidationData Information about the position that was liquidated.


# Function `liquidateVault(uint128 poolId, address collateralType, uint128 liquidateAsAccountId, uint256 maxUsd) → struct ILiquidationModule.LiquidationData liquidationData` {#ILiquidationModule-liquidateVault-uint128-address-uint128-uint256-}
Liquidates an entire vault.


## Parameters:
- `poolId`: The id of the pool whose vault is being liquidated.

- `collateralType`: The address of the collateral whose vault is being liquidated.

- `maxUsd`: The maximum amount of USD that the liquidator is willing to provide for the liquidation, denominated with 18 decimals of precision.


## Return Values:
- liquidationData Information about the vault that was liquidated.


# Function `isPositionLiquidatable(uint128 accountId, uint128 poolId, address collateralType) → bool canLiquidate` {#ILiquidationModule-isPositionLiquidatable-uint128-uint128-address-}
Determines whether a specified position is liquidatable.


## Parameters:
- `accountId`: The id of the account whose position is being queried for liquidation.

- `poolId`: The id of the pool whose position is being queried for liquidation.

- `collateralType`: The address of the collateral backing up the position being queried for liquidation.


## Return Values:
- canLiquidate A boolean with the response to the query.


# Function `isVaultLiquidatable(uint128 poolId, address collateralType) → bool canVaultLiquidate` {#ILiquidationModule-isVaultLiquidatable-uint128-address-}
Determines whether a specified vault is liquidatable.


## Parameters:
- `poolId`: The id of the pool that owns the vault that is being queried for liquidation.

- `collateralType`: The address of the collateral being held at the vault that is being queried for liquidation.


## Return Values:
- canVaultLiquidate A boolean with the response to the query.


