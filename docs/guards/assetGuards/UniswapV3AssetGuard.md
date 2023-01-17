

# Functions:
- [`getBalance(address pool, address asset)`](#UniswapV3AssetGuard-getBalance-address-address-)
- [`getDecimals(address)`](#UniswapV3AssetGuard-getDecimals-address-)
- [`withdrawProcessing(address pool, address asset, uint256 portion, address to)`](#UniswapV3AssetGuard-withdrawProcessing-address-address-uint256-address-)



# Function `getBalance(address pool, address asset) → uint256 balance` {#UniswapV3AssetGuard-getBalance-address-address-}
Returns the pool position of Uniswap v3


## Parameters:
- `pool`: The pool logic address


## Return Values:
- balance The total balance of the pool




# Function `getDecimals(address) → uint256 decimals` {#UniswapV3AssetGuard-getDecimals-address-}
Returns decimal of the Aave lending pool asset





# Function `withdrawProcessing(address pool, address asset, uint256 portion, address to) → address withdrawAsset, uint256 withdrawBalance, struct IAssetGuard.MultiTransaction[] transactions` {#UniswapV3AssetGuard-withdrawProcessing-address-address-uint256-address-}
Creates transaction data for withdrawing tokens



## Return Values:
- withdrawAsset and

- withdrawBalance are used to withdraw portion of asset balance to investor

- transactions is used to execute the withdrawal transaction in PoolLogic




