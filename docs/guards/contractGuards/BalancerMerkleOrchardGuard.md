Transaction guard for Balancer claiming distribution rewards

# Functions:
- [`txGuard(address _poolManagerLogic, address to, bytes data)`](#BalancerMerkleOrchardGuard-txGuard-address-address-bytes-)

# Events:
- [`Claim(address fundAddress, address stakingContract, uint256 time)`](#BalancerMerkleOrchardGuard-Claim-address-address-uint256-)


# Function `txGuard(address _poolManagerLogic, address to, bytes data) → uint16 txType, bool isPublic` {#BalancerMerkleOrchardGuard-txGuard-address-address-bytes-}
Transaction guard for Balancer V2 Merkle Orchard


## Parameters:
- `_poolManagerLogic`: the pool manager logic

- `data`: the transaction data


## Return Values:
- txType the transaction type of a given transaction data. 2 for `Exchange` type

- isPublic if the transaction is public or private


