

# Functions:
- [`withdrawProcessing(address pool, address asset, uint256 portion, address to)`](#BalancerV2GaugeAssetGuard-withdrawProcessing-address-address-uint256-address-)
- [`getBalance(address pool, address asset)`](#BalancerV2GaugeAssetGuard-getBalance-address-address-)



# Function `withdrawProcessing(address pool, address asset, uint256 portion, address to) → address withdrawAsset, uint256 withdrawBalance, struct IAssetGuard.MultiTransaction[] transactions` {#BalancerV2GaugeAssetGuard-withdrawProcessing-address-address-uint256-address-}
Creates transaction data for withdrawing staked tokens


## Parameters:
- `pool`: Pool address

- `asset`: Staked asset

- `portion`: The fraction of total staked asset to withdraw


## Return Values:
- withdrawAsset and

- withdrawBalance are used to withdraw portion of asset balance to investor

- transactions is used to execute the staked withdrawal transaction in PoolLogic


# Function `getBalance(address pool, address asset) → uint256 balance` {#BalancerV2GaugeAssetGuard-getBalance-address-address-}
Returns the balance of the managed asset


## Parameters:
- `pool`: address of the pool

- `asset`: address of the asset


## Return Values:
- balance The asset balance of given pool




