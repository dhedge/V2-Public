

# Functions:
- [`constructor(address _sushiStaking)`](#SushiLPAssetGuard-constructor-address-)
- [`withdrawProcessing(address pool, address asset, uint256 portion, address to)`](#SushiLPAssetGuard-withdrawProcessing-address-address-uint256-address-)
- [`getBalance(address pool, address asset)`](#SushiLPAssetGuard-getBalance-address-address-)
- [`setSushiPoolId(address lpToken, uint256 poolId)`](#SushiLPAssetGuard-setSushiPoolId-address-uint256-)

# Events:
- [`SushiPoolAdded(address lpToken, uint256 poolId)`](#SushiLPAssetGuard-SushiPoolAdded-address-uint256-)


# Function `constructor(address _sushiStaking)` {#SushiLPAssetGuard-constructor-address-}
Initialise for the contract


## Parameters:
- `_sushiStaking`: Sushi's staking MiniChefV2 contract



# Function `withdrawProcessing(address pool, address asset, uint256 portion, address to) → address withdrawAsset, uint256 withdrawBalance, struct IAssetGuard.MultiTransaction[] transactions` {#SushiLPAssetGuard-withdrawProcessing-address-address-uint256-address-}
Creates transaction data for withdrawing staked tokens


## Parameters:
- `pool`: Pool address

- `asset`: Staked asset

- `portion`: The fraction of total staked asset to withdraw

- `to`: The investor address to withdraw to


## Return Values:
- withdrawAsset and

- withdrawBalance are used to withdraw portion of asset balance to investor

- transactions is used to execute the staked withdrawal transaction in PoolLogic


# Function `getBalance(address pool, address asset) → uint256 balance` {#SushiLPAssetGuard-getBalance-address-address-}
Returns the balance of the managed asset


## Parameters:
- `pool`: address of the pool

- `asset`: address of the asset


## Return Values:
- balance The asset balance of given pool


# Function `setSushiPoolId(address lpToken, uint256 poolId)` {#SushiLPAssetGuard-setSushiPoolId-address-uint256-}
Setting sushi pool Id


## Parameters:
- `lpToken`: address of the LP Token

- `poolId`: Id of LP pair pool



