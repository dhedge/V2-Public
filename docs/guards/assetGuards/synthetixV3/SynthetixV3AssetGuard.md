

# Functions:
- [`getBalance(address _pool, address _asset)`](#SynthetixV3AssetGuard-getBalance-address-address-)
- [`getBalanceMutable(address _pool, address _asset)`](#SynthetixV3AssetGuard-getBalanceMutable-address-address-)
- [`getDecimals(address)`](#SynthetixV3AssetGuard-getDecimals-address-)
- [`withdrawProcessing(address _pool, address _asset, uint256 _withdrawPortion, address _to)`](#SynthetixV3AssetGuard-withdrawProcessing-address-address-uint256-address-)



# Function `getBalance(address _pool, address _asset) → uint256` {#SynthetixV3AssetGuard-getBalance-address-address-}
Returns the balance of Synthetix V3 position, accurate balance is not guaranteed


## Parameters:
- `_pool`: Pool address

- `_asset`: Asset address (Basically Synthetix V3 core address)


## Return Values:
- balance Synthetix V3 balance of the pool


# Function `getBalanceMutable(address _pool, address _asset) → uint256` {#SynthetixV3AssetGuard-getBalanceMutable-address-address-}
Returns the balance of Synthetix V3 position in a mutable way


## Parameters:
- `_pool`: Pool address

- `_asset`: Asset address (Basically Synthetix V3 core address)


## Return Values:
- balance Synthetix V3 balance of the pool


# Function `getDecimals(address) → uint256 decimals` {#SynthetixV3AssetGuard-getDecimals-address-}
Returns the decimals of Synthetix V3 position



## Return Values:
- decimals Decimals of the asset


# Function `withdrawProcessing(address _pool, address _asset, uint256 _withdrawPortion, address _to) → address withdrawAsset, uint256 withdrawBalance, struct IAssetGuard.MultiTransaction[] transactions` {#SynthetixV3AssetGuard-withdrawProcessing-address-address-uint256-address-}
Creates transaction data for withdrawing from Synthetix V3 position


## Parameters:
- `_pool`: Pool address

- `_asset`: Asset address (Basically Synthetix V3 core address)

- `_withdrawPortion`: Portion of the asset to withdraw

- `_to`: Investor address to withdraw to


## Return Values:
- withdrawAsset Asset address to withdraw (Basically zero address)

- withdrawBalance Amount to withdraw (Basically zero amount)

- transactions Transactions to be executed (These is where actual token transfer happens)








