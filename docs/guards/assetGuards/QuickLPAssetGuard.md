

# Functions:
- [`constructor(address _stakingRewardsFactory)`](#QuickLPAssetGuard-constructor-address-)
- [`withdrawProcessing(address pool, address asset, uint256 portion, address)`](#QuickLPAssetGuard-withdrawProcessing-address-address-uint256-address-)
- [`getBalance(address pool, address asset)`](#QuickLPAssetGuard-getBalance-address-address-)



# Function `constructor(address _stakingRewardsFactory)` {#QuickLPAssetGuard-constructor-address-}
Initialise for the contract


## Parameters:
- `_stakingRewardsFactory`: Quickswap's staking rewards factory contract



# Function `withdrawProcessing(address pool, address asset, uint256 portion, address) → address withdrawAsset, uint256 withdrawBalance, struct IAssetGuard.MultiTransaction[] transactions` {#QuickLPAssetGuard-withdrawProcessing-address-address-uint256-address-}
Creates transaction data for withdrawing staked tokens


## Parameters:
- `pool`: Pool address

- `asset`: Staked asset

- `portion`: The fraction of total staked asset to withdraw


## Return Values:
- withdrawAsset and

- withdrawBalance are used to withdraw portion of asset balance to investor

- transactions is used to execute the staked withdrawal transaction in PoolLogic


# Function `getBalance(address pool, address asset) → uint256 balance` {#QuickLPAssetGuard-getBalance-address-address-}
Returns the balance of the managed asset


## Parameters:
- `pool`: address of the pool

- `asset`: address of the asset


## Return Values:
- balance The asset balance of given pool


