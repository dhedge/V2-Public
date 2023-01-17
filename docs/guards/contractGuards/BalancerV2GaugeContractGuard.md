

# Functions:
- [`txGuard(address _poolManagerLogic, address to, bytes data)`](#BalancerV2GaugeContractGuard-txGuard-address-address-bytes-)

# Events:
- [`Claim(address fundAddress, address stakingContract, uint256 time)`](#BalancerV2GaugeContractGuard-Claim-address-address-uint256-)
- [`Stake(address fundAddress, address stakingToken, address stakingContract, uint256 amount, uint256 time)`](#BalancerV2GaugeContractGuard-Stake-address-address-address-uint256-uint256-)
- [`Unstake(address fundAddress, address stakingToken, address stakingContract, uint256 amount, uint256 time)`](#BalancerV2GaugeContractGuard-Unstake-address-address-address-uint256-uint256-)


# Function `txGuard(address _poolManagerLogic, address to, bytes data) → uint16 txType, bool isPublic` {#BalancerV2GaugeContractGuard-txGuard-address-address-bytes-}
Transaction guard for Balancer V2 Reward Gauge


## Parameters:
- `_poolManagerLogic`: the pool manager logic

- `to`: The contract to send transaction to

- `data`: The transaction data


## Return Values:
- txType the transaction type of a given transaction data. 5 for `Deposit`, 6 for `Withdraw`, 7 for `Claim`

- isPublic if the transaction is public or private




