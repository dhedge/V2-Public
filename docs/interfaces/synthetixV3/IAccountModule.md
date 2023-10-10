Manages the system's account token NFT. Every user will need to register an account before being able to interact with the system.

# Functions:
- [`getAccountPermissions(uint128 accountId)`](#IAccountModule-getAccountPermissions-uint128-)
- [`createAccount(uint128 requestedAccountId)`](#IAccountModule-createAccount-uint128-)
- [`createAccount()`](#IAccountModule-createAccount--)
- [`notifyAccountTransfer(address to, uint128 accountId)`](#IAccountModule-notifyAccountTransfer-address-uint128-)
- [`grantPermission(uint128 accountId, bytes32 permission, address user)`](#IAccountModule-grantPermission-uint128-bytes32-address-)
- [`revokePermission(uint128 accountId, bytes32 permission, address user)`](#IAccountModule-revokePermission-uint128-bytes32-address-)
- [`renouncePermission(uint128 accountId, bytes32 permission)`](#IAccountModule-renouncePermission-uint128-bytes32-)
- [`hasPermission(uint128 accountId, bytes32 permission, address user)`](#IAccountModule-hasPermission-uint128-bytes32-address-)
- [`isAuthorized(uint128 accountId, bytes32 permission, address target)`](#IAccountModule-isAuthorized-uint128-bytes32-address-)
- [`getAccountTokenAddress()`](#IAccountModule-getAccountTokenAddress--)
- [`getAccountOwner(uint128 accountId)`](#IAccountModule-getAccountOwner-uint128-)
- [`getAccountLastInteraction(uint128 accountId)`](#IAccountModule-getAccountLastInteraction-uint128-)



# Function `getAccountPermissions(uint128 accountId) → struct IAccountModule.AccountPermissions[] accountPerms` {#IAccountModule-getAccountPermissions-uint128-}
Returns an array of `AccountPermission` for the provided `accountId`.


## Parameters:
- `accountId`: The id of the account whose permissions are being retrieved.


## Return Values:
- accountPerms An array of AccountPermission objects describing the permissions granted to the account.


# Function `createAccount(uint128 requestedAccountId)` {#IAccountModule-createAccount-uint128-}
Mints an account token with id `requestedAccountId` to `msg.sender`.


## Parameters:
- `requestedAccountId`: The id requested for the account being created. Reverts if id already exists.

Requirements:

- `requestedAccountId` must not already be minted.
- `requestedAccountId` must be less than type(uint128).max / 2

Emits a {AccountCreated} event.



# Function `createAccount() → uint128 accountId` {#IAccountModule-createAccount--}
Mints an account token with an available id to `msg.sender`.

Emits a {AccountCreated} event.




# Function `notifyAccountTransfer(address to, uint128 accountId)` {#IAccountModule-notifyAccountTransfer-address-uint128-}
Called by AccountTokenModule to notify the system when the account token is transferred.


## Parameters:
- `to`: The new holder of the account NFT.

- `accountId`: The id of the account that was just transferred.

Requirements:

- `msg.sender` must be the account token.



# Function `grantPermission(uint128 accountId, bytes32 permission, address user)` {#IAccountModule-grantPermission-uint128-bytes32-address-}
Grants `permission` to `user` for account `accountId`.


## Parameters:
- `accountId`: The id of the account that granted the permission.

- `permission`: The bytes32 identifier of the permission.

- `user`: The target address that received the permission.

Requirements:

- `msg.sender` must own the account token with ID `accountId` or have the "admin" permission.

Emits a {PermissionGranted} event.



# Function `revokePermission(uint128 accountId, bytes32 permission, address user)` {#IAccountModule-revokePermission-uint128-bytes32-address-}
Revokes `permission` from `user` for account `accountId`.


## Parameters:
- `accountId`: The id of the account that revoked the permission.

- `permission`: The bytes32 identifier of the permission.

- `user`: The target address that no longer has the permission.

Requirements:

- `msg.sender` must own the account token with ID `accountId` or have the "admin" permission.

Emits a {PermissionRevoked} event.



# Function `renouncePermission(uint128 accountId, bytes32 permission)` {#IAccountModule-renouncePermission-uint128-bytes32-}
Revokes `permission` from `msg.sender` for account `accountId`.


## Parameters:
- `accountId`: The id of the account whose permission was renounced.

- `permission`: The bytes32 identifier of the permission.

Emits a {PermissionRevoked} event.



# Function `hasPermission(uint128 accountId, bytes32 permission, address user) → bool` {#IAccountModule-hasPermission-uint128-bytes32-address-}
Returns `true` if `user` has been granted `permission` for account `accountId`.


## Parameters:
- `accountId`: The id of the account whose permission is being queried.

- `permission`: The bytes32 identifier of the permission.

- `user`: The target address whose permission is being queried.


## Return Values:
- hasPermission A boolean with the response of the query.


# Function `isAuthorized(uint128 accountId, bytes32 permission, address target) → bool` {#IAccountModule-isAuthorized-uint128-bytes32-address-}
Returns `true` if `target` is authorized to `permission` for account `accountId`.


## Parameters:
- `accountId`: The id of the account whose permission is being queried.

- `permission`: The bytes32 identifier of the permission.

- `target`: The target address whose permission is being queried.


## Return Values:
- isAuthorized A boolean with the response of the query.


# Function `getAccountTokenAddress() → address accountNftToken` {#IAccountModule-getAccountTokenAddress--}
Returns the address for the account token used by the module.



## Return Values:
- accountNftToken The address of the account token.


# Function `getAccountOwner(uint128 accountId) → address owner` {#IAccountModule-getAccountOwner-uint128-}
Returns the address that owns a given account, as recorded by the system.


## Parameters:
- `accountId`: The account id whose owner is being retrieved.


## Return Values:
- owner The owner of the given account id.


# Function `getAccountLastInteraction(uint128 accountId) → uint256 timestamp` {#IAccountModule-getAccountLastInteraction-uint128-}
Returns the last unix timestamp that a permissioned action was taken with this account


## Parameters:
- `accountId`: The account id to check


## Return Values:
- timestamp The unix timestamp of the last time a permissioned action occured with the account


