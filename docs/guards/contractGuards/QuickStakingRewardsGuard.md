

# Functions:
- [`txGuard(address _poolManagerLogic, address to, bytes data)`](#QuickStakingRewardsGuard-txGuard-address-address-bytes-)

# Events:
- [`Stake(address fundAddress, address asset, address stakingContract, uint256 amount, uint256 time)`](#QuickStakingRewardsGuard-Stake-address-address-address-uint256-uint256-)
- [`Unstake(address fundAddress, address asset, address stakingContract, uint256 amount, uint256 time)`](#QuickStakingRewardsGuard-Unstake-address-address-address-uint256-uint256-)
- [`Claim(address fundAddress, address stakingContract, uint256 time)`](#QuickStakingRewardsGuard-Claim-address-address-uint256-)


# Function `txGuard(address _poolManagerLogic, address to, bytes data) → uint16 txType, bool isPublic` {#QuickStakingRewardsGuard-txGuard-address-address-bytes-}
Transaction guard for Sushi MiniChefV2


## Parameters:
- `_poolManagerLogic`: the pool manager logic

- `to`: The contract to send transaction to

- `data`: The transaction data


## Return Values:
- txType the transaction type of a given transaction data. 5 for `Stake` type, 6 for `Unstake`, 7 for `Claim`

- isPublic if the transaction is public or private


