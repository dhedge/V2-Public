Transaction guard for Velodrome Gauge

# Functions:
- [`txGuard(address _poolManagerLogic, address to, bytes data)`](#VelodromeGaugeContractGuard-txGuard-address-address-bytes-)

# Events:
- [`Claim(address fundAddress, address stakingContract, uint256 time)`](#VelodromeGaugeContractGuard-Claim-address-address-uint256-)
- [`Stake(address fundAddress, address stakingToken, address stakingContract, uint256 amount, uint256 time)`](#VelodromeGaugeContractGuard-Stake-address-address-address-uint256-uint256-)
- [`Unstake(address fundAddress, address stakingToken, address stakingContract, uint256 amount, uint256 time)`](#VelodromeGaugeContractGuard-Unstake-address-address-address-uint256-uint256-)


# Function `txGuard(address _poolManagerLogic, address to, bytes data) → uint16 txType, bool` {#VelodromeGaugeContractGuard-txGuard-address-address-bytes-}
Transaction guard for Velodrome


## Parameters:
- `_poolManagerLogic`: the pool manager logic

- `to`: the gauge address

- `data`: the transaction data


## Return Values:
- txType the transaction type of a given transaction data. 2 for `Exchange` type, 3 for `Add Liquidity`, 4 for `Remove Liquidity`

- isPublic if the transaction is public or private


