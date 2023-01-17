

# Functions:
- [`txGuard(address _poolManagerLogic, address to, bytes data)`](#ArrakisLiquidityGaugeV4ContractGuard-txGuard-address-address-bytes-)

# Events:
- [`Claim(address fundAddress, address stakingContract, uint256 time)`](#ArrakisLiquidityGaugeV4ContractGuard-Claim-address-address-uint256-)


# Function `txGuard(address _poolManagerLogic, address to, bytes data) → uint16 txType, bool isPublic` {#ArrakisLiquidityGaugeV4ContractGuard-txGuard-address-address-bytes-}
Transaction guard for Arrakis Finance Liquidity gauge


## Parameters:
- `_poolManagerLogic`: the pool manager logic

- `to`: The contract to send transaction to

- `data`: The transaction data


## Return Values:
- txType the transaction type of a given transaction data. 7 for `Claim`

- isPublic if the transaction is public or private




