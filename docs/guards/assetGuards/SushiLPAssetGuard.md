Asset type = 2

# Functions:
- [`constructor(address _sushiStaking, struct SushiLPAssetGuard.SushiPool[] sushiPools)`](#SushiLPAssetGuard-constructor-address-struct-SushiLPAssetGuard-SushiPool---)
- [`getWithdrawStakedTx(address pool, address asset, uint256 withdrawPortion, address to)`](#SushiLPAssetGuard-getWithdrawStakedTx-address-address-uint256-address-)
- [`getBalance(address pool, address asset)`](#SushiLPAssetGuard-getBalance-address-address-)

# Events:
- [`WithdrawStaked(address fundAddress, address asset, address to, uint256 withdrawAmount, uint256 time)`](#SushiLPAssetGuard-WithdrawStaked-address-address-address-uint256-uint256-)

# Function `constructor(address _sushiStaking, struct SushiLPAssetGuard.SushiPool[] sushiPools)` {#SushiLPAssetGuard-constructor-address-struct-SushiLPAssetGuard-SushiPool---}
No description
## Parameters:
- `_sushiStaking`: Sushi's staking MiniChefV2 contract

- `sushiPools`: For mapping Sushi LP tokens to MiniChefV2 pool IDs
# Function `getWithdrawStakedTx(address pool, address asset, uint256 withdrawPortion, address to) → address stakingContract, bytes txData` {#SushiLPAssetGuard-getWithdrawStakedTx-address-address-uint256-address-}
The same interface can be used for other types of stakeable tokens

## Parameters:
- `pool`: Pool address

- `asset`: Staked asset

- `withdrawPortion`: The fraction of total staked asset to withdraw

- `to`: The investor address to withdraw to

## Return Values:
- stakingContract and txData are used to execute the staked withdrawal transaction in PoolLogic
# Function `getBalance(address pool, address asset) → uint256 balance` {#SushiLPAssetGuard-getBalance-address-address-}
May include any external balance in staking contracts

# Event `WithdrawStaked(address fundAddress, address asset, address to, uint256 withdrawAmount, uint256 time)` {#SushiLPAssetGuard-WithdrawStaked-address-address-address-uint256-uint256-}
No description
