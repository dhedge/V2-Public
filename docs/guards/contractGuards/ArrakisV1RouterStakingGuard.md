

# Functions:
- [`txGuard(address _poolManagerLogic, address to, bytes data)`](#ArrakisV1RouterStakingGuard-txGuard-address-address-bytes-)

# Events:
- [`Stake(address fundAddress, address stakingToken, address stakingContract, uint256 time)`](#ArrakisV1RouterStakingGuard-Stake-address-address-address-uint256-)
- [`Unstake(address fundAddress, address stakingToken, address stakingContract, uint256 amount, uint256 time)`](#ArrakisV1RouterStakingGuard-Unstake-address-address-address-uint256-uint256-)


# Function `txGuard(address _poolManagerLogic, address to, bytes data) → uint16 txType, bool` {#ArrakisV1RouterStakingGuard-txGuard-address-address-bytes-}
Transaction guard for Arrakis Finance V1 Router Staking


## Parameters:
- `_poolManagerLogic`: the pool manager logic

- `to`: The contract to send transaction to

- `data`: The transaction data


## Return Values:
- txType the transaction type of a given transaction data. 5 for `Stake` type, 6 for `Unstake`

- isPublic if the transaction is public or private




