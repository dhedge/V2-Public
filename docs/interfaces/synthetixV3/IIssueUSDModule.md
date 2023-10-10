

# Functions:
- [`mintUsd(uint128 accountId, uint128 poolId, address collateralType, uint256 amount)`](#IIssueUSDModule-mintUsd-uint128-uint128-address-uint256-)
- [`burnUsd(uint128 accountId, uint128 poolId, address collateralType, uint256 amount)`](#IIssueUSDModule-burnUsd-uint128-uint128-address-uint256-)



# Function `mintUsd(uint128 accountId, uint128 poolId, address collateralType, uint256 amount)` {#IIssueUSDModule-mintUsd-uint128-uint128-address-uint256-}
Mints {amount} of snxUSD with the specified liquidity position.


## Parameters:
- `accountId`: The id of the account that is minting snxUSD.

- `poolId`: The id of the pool whose collateral will be used to back up the mint.

- `collateralType`: The address of the collateral that will be used to back up the mint.

- `amount`: The amount of snxUSD to be minted, denominated with 18 decimals of precision.

Requirements:

- `msg.sender` must be the owner of the account, have the `ADMIN` permission, or have the `MINT` permission.
- After minting, the collateralization ratio of the liquidity position must not be below the target collateralization ratio for the corresponding collateral type.

Emits a {UsdMinted} event.



# Function `burnUsd(uint128 accountId, uint128 poolId, address collateralType, uint256 amount)` {#IIssueUSDModule-burnUsd-uint128-uint128-address-uint256-}
Burns {amount} of snxUSD with the specified liquidity position.


## Parameters:
- `accountId`: The id of the account that is burning snxUSD.

- `poolId`: The id of the pool whose collateral was used to back up the snxUSD.

- `collateralType`: The address of the collateral that was used to back up the snxUSD.

- `amount`: The amount of snxUSD to be burnt, denominated with 18 decimals of precision.

Emits a {UsdMinted} event.



