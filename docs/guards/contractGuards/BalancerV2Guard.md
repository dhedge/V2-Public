Transaction guard for Balancer V2 Vault

# Functions:
- [`constructor(uint256 _slippageLimitNumerator, uint256 _slippageLimitDenominator)`](#BalancerV2Guard-constructor-uint256-uint256-)
- [`txGuard(address _poolManagerLogic, address to, bytes data)`](#BalancerV2Guard-txGuard-address-address-bytes-)

# Events:
- [`JoinPool(address fundAddress, bytes32 poolId, address[] assets, uint256[] maxAmountsIn, uint256 time)`](#BalancerV2Guard-JoinPool-address-bytes32-address---uint256---uint256-)
- [`ExitPool(address fundAddress, bytes32 poolId, address[] assets, uint256[] minAmountsOut, uint256 time)`](#BalancerV2Guard-ExitPool-address-bytes32-address---uint256---uint256-)


# Function `constructor(uint256 _slippageLimitNumerator, uint256 _slippageLimitDenominator)` {#BalancerV2Guard-constructor-uint256-uint256-}
No description




# Function `txGuard(address _poolManagerLogic, address to, bytes data) → uint16 txType, bool` {#BalancerV2Guard-txGuard-address-address-bytes-}
Transaction guard for Balancer V2 Vault


## Parameters:
- `_poolManagerLogic`: the pool manager logic

- `data`: the transaction data


## Return Values:
- txType the transaction type of a given transaction data. 2 for `Exchange` type

- isPublic if the transaction is public or private




