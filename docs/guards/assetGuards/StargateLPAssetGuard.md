

# Functions:
- [`constructor(address _stargateLpStaking)`](#StargateLPAssetGuard-constructor-address-)
- [`updateStakingPoolIds()`](#StargateLPAssetGuard-updateStakingPoolIds--)
- [`withdrawProcessing(address pool, address asset, uint256 portion, address)`](#StargateLPAssetGuard-withdrawProcessing-address-address-uint256-address-)
- [`getBalance(address pool, address asset)`](#StargateLPAssetGuard-getBalance-address-address-)
- [`getDecimals(address asset)`](#StargateLPAssetGuard-getDecimals-address-)

# Events:
- [`StargatePoolAdded(address lpToken, uint256 poolId)`](#StargateLPAssetGuard-StargatePoolAdded-address-uint256-)


# Function `constructor(address _stargateLpStaking)` {#StargateLPAssetGuard-constructor-address-}
Initialiser for the contract


## Parameters:
- `_stargateLpStaking`: Stargate's staking contract (similar to Sushi's MiniChef)



# Function `updateStakingPoolIds()` {#StargateLPAssetGuard-updateStakingPoolIds--}
Public function to update staking contract pool Ids if they ever change




# Function `withdrawProcessing(address pool, address asset, uint256 portion, address) → address withdrawAsset, uint256 withdrawBalance, struct IAssetGuard.MultiTransaction[] transactions` {#StargateLPAssetGuard-withdrawProcessing-address-address-uint256-address-}
Creates transaction data for withdrawing staked tokens


## Parameters:
- `pool`: Pool address

- `asset`: Staked asset

- `portion`: The fraction of total staked asset to withdraw


## Return Values:
- withdrawAsset and

- withdrawBalance are used to withdraw portion of asset balance to investor

- transactions is used to execute the staked withdrawal transaction in PoolLogic


# Function `getBalance(address pool, address asset) → uint256 balance` {#StargateLPAssetGuard-getBalance-address-address-}
Returns the balance of the managed asset (in underlying asset eg USDC, DAI)


## Parameters:
- `pool`: address of the pool

- `asset`: address of the asset


## Return Values:
- balance The asset balance of given pool


# Function `getDecimals(address asset) → uint256 decimals` {#StargateLPAssetGuard-getDecimals-address-}
Returns decimal of the asset





