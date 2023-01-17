

# Functions:
- [`txGuard(address _poolManagerLogic, address, bytes data)`](#ERC20Guard-txGuard-address-address-bytes-)
- [`withdrawProcessing(address pool, address asset, uint256 portion, address)`](#ERC20Guard-withdrawProcessing-address-address-uint256-address-)
- [`getBalance(address pool, address asset)`](#ERC20Guard-getBalance-address-address-)
- [`getDecimals(address asset)`](#ERC20Guard-getDecimals-address-)
- [`removeAssetCheck(address pool, address asset)`](#ERC20Guard-removeAssetCheck-address-address-)

# Events:
- [`Approve(address fundAddress, address manager, address spender, uint256 amount, uint256 time)`](#ERC20Guard-Approve-address-address-address-uint256-uint256-)


# Function `txGuard(address _poolManagerLogic, address, bytes data) → uint16 txType, bool` {#ERC20Guard-txGuard-address-address-bytes-}
Transaction guard for approving assets


## Parameters:
- `_poolManagerLogic`: Pool address

- `data`: Transaction call data attempt by manager


## Return Values:
- txType transaction type described in PoolLogic

- isPublic if the transaction is public or private


# Function `withdrawProcessing(address pool, address asset, uint256 portion, address) → address withdrawAsset, uint256 withdrawBalance, struct IAssetGuard.MultiTransaction[] transactions` {#ERC20Guard-withdrawProcessing-address-address-uint256-address-}
Creates transaction data for withdrawing tokens



## Return Values:
- withdrawAsset and

- withdrawBalance are used to withdraw portion of asset balance to investor

- transactions is used to execute the withdrawal transaction in PoolLogic


# Function `getBalance(address pool, address asset) → uint256 balance` {#ERC20Guard-getBalance-address-address-}
Returns the balance of the managed asset



## Return Values:
- balance The asset balance of given pool


# Function `getDecimals(address asset) → uint256 decimals` {#ERC20Guard-getDecimals-address-}
Returns the decimal of the managed asset


## Parameters:
- `asset`: Address of the managed asset


## Return Values:
- decimals The decimal of given asset


# Function `removeAssetCheck(address pool, address asset)` {#ERC20Guard-removeAssetCheck-address-address-}
Necessary check for remove asset


## Parameters:
- `pool`: Address of the pool

- `asset`: Address of the remove asset



