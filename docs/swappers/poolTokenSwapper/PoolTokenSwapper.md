This contract allows for swapping between assets and pools with configurable swap fees and assets

# Functions:
- [`initialize(address _factory, address _manager, struct PoolTokenSwapper.AssetConfig[] _assetConfigs, struct PoolTokenSwapper.PoolConfig[] _poolConfigs, struct PoolTokenSwapper.SwapWhitelistConfig[] _swapWhitelist)`](#PoolTokenSwapper-initialize-address-address-struct-PoolTokenSwapper-AssetConfig---struct-PoolTokenSwapper-PoolConfig---struct-PoolTokenSwapper-SwapWhitelistConfig---)
- [`swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut)`](#PoolTokenSwapper-swap-address-address-uint256-uint256-)
- [`execTransaction(address to, bytes data)`](#PoolTokenSwapper-execTransaction-address-bytes-)
- [`setAssets(struct PoolTokenSwapper.AssetConfig[] _assetConfigs)`](#PoolTokenSwapper-setAssets-struct-PoolTokenSwapper-AssetConfig---)
- [`setPools(struct PoolTokenSwapper.PoolConfig[] _poolConfigs)`](#PoolTokenSwapper-setPools-struct-PoolTokenSwapper-PoolConfig---)
- [`setManager(address _manager)`](#PoolTokenSwapper-setManager-address-)
- [`setSwapWhitelist(struct PoolTokenSwapper.SwapWhitelistConfig[] _swapWhitelist)`](#PoolTokenSwapper-setSwapWhitelist-struct-PoolTokenSwapper-SwapWhitelistConfig---)
- [`salvage(contract IERC20Upgradeable _token, uint256 _amount)`](#PoolTokenSwapper-salvage-contract-IERC20Upgradeable-uint256-)
- [`pause()`](#PoolTokenSwapper-pause--)
- [`unpause()`](#PoolTokenSwapper-unpause--)
- [`factory()`](#PoolTokenSwapper-factory--)
- [`isSupportedAsset(address asset)`](#PoolTokenSwapper-isSupportedAsset-address-)
- [`getSwapQuote(address tokenIn, address tokenOut, uint256 amountIn)`](#PoolTokenSwapper-getSwapQuote-address-address-uint256-)

# Events:
- [`TokenSwapperTransactionExecuted(address swapper, address manager, uint16 transactionType)`](#PoolTokenSwapper-TokenSwapperTransactionExecuted-address-address-uint16-)
- [`Swap(address user, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut)`](#PoolTokenSwapper-Swap-address-address-address-uint256-uint256-)


# Function `initialize(address _factory, address _manager, struct PoolTokenSwapper.AssetConfig[] _assetConfigs, struct PoolTokenSwapper.PoolConfig[] _poolConfigs, struct PoolTokenSwapper.SwapWhitelistConfig[] _swapWhitelist)` {#PoolTokenSwapper-initialize-address-address-struct-PoolTokenSwapper-AssetConfig---struct-PoolTokenSwapper-PoolConfig---struct-PoolTokenSwapper-SwapWhitelistConfig---}
No description

## Parameters:
- `_factory`: The address of the pool factory contract

- `_manager`: The address of the manager allowed to execute transactions

- `_assetConfigs`: An array of AssetConfig structs containing the addresses of the assets

- `_poolConfigs`: An array of PoolConfig structs containing the addresses of the pools and their swap fees

- `_swapWhitelist`: An array of SwapWhitelistConfig structs containing the addresses and their swap whitelist status



# Function `swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut) → uint256 amountOut` {#PoolTokenSwapper-swap-address-address-uint256-uint256-}
Swaps between two assets or pools


## Parameters:
- `tokenIn`: Token to be swapped from

- `tokenOut`: Token to be swapped to

- `amountIn`: Amount of tokenIn to swap

- `minAmountOut`: Minimum expected amount out from swap


## Return Values:
- amountOut The amount of tokenOut received from the swap








# Function `execTransaction(address to, bytes data) → bool success` {#PoolTokenSwapper-execTransaction-address-bytes-}
Function to let the pool manager execute whitelisted third party protocol functions eg swaps


## Parameters:
- `to`: The destination address for pool to interact with

- `data`: The data that going to be sent in the transaction


## Return Values:
- success A boolean for success or failure of the transaction


# Function `setAssets(struct PoolTokenSwapper.AssetConfig[] _assetConfigs)` {#PoolTokenSwapper-setAssets-struct-PoolTokenSwapper-AssetConfig---}
Sets the addresses and enabled statuses of the assets


## Parameters:
- `_assetConfigs`: An array of AssetConfig structs containing the addresses of the assets



# Function `setPools(struct PoolTokenSwapper.PoolConfig[] _poolConfigs)` {#PoolTokenSwapper-setPools-struct-PoolTokenSwapper-PoolConfig---}
Sets the addresses and enabled statuses of the pools and their swap fees


## Parameters:
- `_poolConfigs`: An array of PoolConfig structs containing the addresses of the pools and their swap fees



# Function `setManager(address _manager)` {#PoolTokenSwapper-setManager-address-}
Sets the manager account to manage the assets inside the vault


## Parameters:
- `_manager`: The manager account



# Function `setSwapWhitelist(struct PoolTokenSwapper.SwapWhitelistConfig[] _swapWhitelist)` {#PoolTokenSwapper-setSwapWhitelist-struct-PoolTokenSwapper-SwapWhitelistConfig---}
Sets the addresses which can swap with this contract


## Parameters:
- `_swapWhitelist`: An array of SwapWhitelistConfig structs containing the addresses and their swap whitelist status



# Function `salvage(contract IERC20Upgradeable _token, uint256 _amount)` {#PoolTokenSwapper-salvage-contract-IERC20Upgradeable-uint256-}
Allows the contract owner to withdraw any ERC20 token in the contract


## Parameters:
- `_token`: The address of the ERC20 token

- `_amount`: The amount of the ERC20 token to withdraw



# Function `pause()` {#PoolTokenSwapper-pause--}
Pauses the contract





# Function `unpause()` {#PoolTokenSwapper-unpause--}
Unpauses the contract





# Function `factory() → address` {#PoolTokenSwapper-factory--}
The dHEDGE pool factory



## Return Values:
- The address of the pool factory


# Function `isSupportedAsset(address asset) → bool supported` {#PoolTokenSwapper-isSupportedAsset-address-}
Returns true for any asset supported by dHedge


## Parameters:
- `asset`: The address of the asset


## Return Values:
- supported if the asset is supported by dHedge


# Function `getSwapQuote(address tokenIn, address tokenOut, uint256 amountIn) → uint256 amountOut` {#PoolTokenSwapper-getSwapQuote-address-address-uint256-}
Gets an amount out quote for any type of swap (pool or asset)
The quote includes swap fees


## Parameters:
- `tokenIn`: swap from token address (pool or asset)

- `tokenOut`: swap to token address (pool or asset)

- `amountIn`: swap from token amount


## Return Values:
- amountOut swap to quote amount








