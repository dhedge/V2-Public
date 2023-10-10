

# Functions:
- [`constructor(address _voter)`](#VelodromeV2LPAssetGuard-constructor-address-)
- [`withdrawProcessing(address pool, address asset, uint256 portion, address to)`](#VelodromeV2LPAssetGuard-withdrawProcessing-address-address-uint256-address-)
- [`getBalance(address pool, address asset)`](#VelodromeV2LPAssetGuard-getBalance-address-address-)



# Function `constructor(address _voter)` {#VelodromeV2LPAssetGuard-constructor-address-}
No description




# Function `withdrawProcessing(address pool, address asset, uint256 portion, address to) → address withdrawAsset, uint256 withdrawBalance, struct IAssetGuard.MultiTransaction[] transactions` {#VelodromeV2LPAssetGuard-withdrawProcessing-address-address-uint256-address-}
Creates transaction data for withdrawing Velodrome V2 LP tokens


## Parameters:
- `pool`: Pool address

- `asset`: Velodrome LP asset

- `portion`: The fraction of total Velodrome V2 LP asset to withdraw

- `to`: The investor address to withdraw to


## Return Values:
- withdrawAsset and

- withdrawBalance are used to withdraw portion of asset balance to investor

- transactions are used to execute the Velodrome V2 LP withdrawal transaction in PoolLogic




# Function `getBalance(address pool, address asset) → uint256 balance` {#VelodromeV2LPAssetGuard-getBalance-address-address-}
Returns the balance of the managed asset


## Parameters:
- `pool`: address of the pool

- `asset`: address of the asset


## Return Values:
- balance The asset balance of given pool in lp price


