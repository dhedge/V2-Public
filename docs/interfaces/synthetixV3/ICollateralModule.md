Allows users to deposit and withdraw collateral from the system.

# Functions:
- [`deposit(uint128 accountId, address collateralType, uint256 tokenAmount)`](#ICollateralModule-deposit-uint128-address-uint256-)
- [`withdraw(uint128 accountId, address collateralType, uint256 tokenAmount)`](#ICollateralModule-withdraw-uint128-address-uint256-)
- [`getAccountCollateral(uint128 accountId, address collateralType)`](#ICollateralModule-getAccountCollateral-uint128-address-)
- [`getAccountAvailableCollateral(uint128 accountId, address collateralType)`](#ICollateralModule-getAccountAvailableCollateral-uint128-address-)
- [`cleanExpiredLocks(uint128 accountId, address collateralType, uint256 offset, uint256 count)`](#ICollateralModule-cleanExpiredLocks-uint128-address-uint256-uint256-)
- [`createLock(uint128 accountId, address collateralType, uint256 amount, uint64 expireTimestamp)`](#ICollateralModule-createLock-uint128-address-uint256-uint64-)



# Function `deposit(uint128 accountId, address collateralType, uint256 tokenAmount)` {#ICollateralModule-deposit-uint128-address-uint256-}
Deposits `tokenAmount` of collateral of type `collateralType` into account `accountId`.


## Parameters:
- `accountId`: The id of the account that is making the deposit.

- `collateralType`: The address of the token to be deposited.

- `tokenAmount`: The amount being deposited, denominated in the token's native decimal representation.

Emits a {Deposited} event.



# Function `withdraw(uint128 accountId, address collateralType, uint256 tokenAmount)` {#ICollateralModule-withdraw-uint128-address-uint256-}
Withdraws `tokenAmount` of collateral of type `collateralType` from account `accountId`.


## Parameters:
- `accountId`: The id of the account that is making the withdrawal.

- `collateralType`: The address of the token to be withdrawn.

- `tokenAmount`: The amount being withdrawn, denominated in the token's native decimal representation.

Requirements:

- `msg.sender` must be the owner of the account, have the `ADMIN` permission, or have the `WITHDRAW` permission.

Emits a {Withdrawn} event.




# Function `getAccountCollateral(uint128 accountId, address collateralType) → uint256 totalDeposited, uint256 totalAssigned, uint256 totalLocked` {#ICollateralModule-getAccountCollateral-uint128-address-}
Returns the total values pertaining to account `accountId` for `collateralType`.


## Parameters:
- `accountId`: The id of the account whose collateral is being queried.

- `collateralType`: The address of the collateral type whose amount is being queried.


## Return Values:
- totalDeposited The total collateral deposited in the account, denominated with 18 decimals of precision.

- totalAssigned The amount of collateral in the account that is delegated to pools, denominated with 18 decimals of precision.

- totalLocked The amount of collateral in the account that cannot currently be undelegated from a pool, denominated with 18 decimals of precision.


# Function `getAccountAvailableCollateral(uint128 accountId, address collateralType) → uint256 amountD18` {#ICollateralModule-getAccountAvailableCollateral-uint128-address-}
Returns the amount of collateral of type `collateralType` deposited with account `accountId` that can be withdrawn or delegated to pools.


## Parameters:
- `accountId`: The id of the account whose collateral is being queried.

- `collateralType`: The address of the collateral type whose amount is being queried.


## Return Values:
- amountD18 The amount of collateral that is available for withdrawal or delegation, denominated with 18 decimals of precision.


# Function `cleanExpiredLocks(uint128 accountId, address collateralType, uint256 offset, uint256 count) → uint256 cleared` {#ICollateralModule-cleanExpiredLocks-uint128-address-uint256-uint256-}
Clean expired locks from locked collateral arrays for an account/collateral type. It includes offset and items to prevent gas exhaustion. If both, offset and items, are 0 it will traverse the whole array (unlimited).


## Parameters:
- `accountId`: The id of the account whose locks are being cleared.

- `collateralType`: The address of the collateral type to clean locks for.

- `offset`: The index of the first lock to clear.

- `count`: The number of slots to check for cleaning locks. Set to 0 to clean all locks at/after offset


## Return Values:
- cleared the number of locks that were actually expired (and therefore cleared)


# Function `createLock(uint128 accountId, address collateralType, uint256 amount, uint64 expireTimestamp)` {#ICollateralModule-createLock-uint128-address-uint256-uint64-}
Create a new lock on the given account. you must have `admin` permission on the specified account to create a lock.


## Parameters:
- `accountId`: The id of the account for which a lock is to be created.

- `collateralType`: The address of the collateral type for which the lock will be created.

- `amount`: The amount of collateral tokens to wrap in the lock being created, denominated with 18 decimals of precision.

- `expireTimestamp`: The date in which the lock will become clearable.



