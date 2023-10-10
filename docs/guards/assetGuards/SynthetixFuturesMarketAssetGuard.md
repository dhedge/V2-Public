

# Functions:
- [`withdrawProcessing(address pool, address asset, uint256 portion, address withdrawerAddress)`](#SynthetixFuturesMarketAssetGuard-withdrawProcessing-address-address-uint256-address-)
- [`getBalance(address pool, address asset)`](#SynthetixFuturesMarketAssetGuard-getBalance-address-address-)
- [`getDecimals(address)`](#SynthetixFuturesMarketAssetGuard-getDecimals-address-)



# Function `withdrawProcessing(address pool, address asset, uint256 portion, address withdrawerAddress) → address withdrawAsset, uint256 withdrawBalance, struct IAssetGuard.MultiTransaction[] transactions` {#SynthetixFuturesMarketAssetGuard-withdrawProcessing-address-address-uint256-address-}
Creates transaction data for reducing a futures position by the portion


## Parameters:
- `pool`: Pool address

- `asset`: FuturesMarket

- `portion`: The fraction of total future asset to withdraw


## Return Values:
- withdrawAsset and

- withdrawBalance are used to withdraw portion of asset balance to investor

- transactions is used to execute the reduction of the futures position in PoolLogic


# Function `getBalance(address pool, address asset) → uint256 balance` {#SynthetixFuturesMarketAssetGuard-getBalance-address-address-}
Returns the sUSD value of the Future if it was closed now


## Parameters:
- `pool`: address of the pool

- `asset`: address of the asset


## Return Values:
- balance The asset balance of given pool


# Function `getDecimals(address) → uint256 decimals` {#SynthetixFuturesMarketAssetGuard-getDecimals-address-}
Returns decimal of the FuturesMarket Asset





