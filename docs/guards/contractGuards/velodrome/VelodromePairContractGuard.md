

# Functions:
- [`txGuard(address _poolManagerLogic, address _to, bytes _data)`](#VelodromePairContractGuard-txGuard-address-address-bytes-)



# Function `txGuard(address _poolManagerLogic, address _to, bytes _data) → uint16 txType, bool isPublic` {#VelodromePairContractGuard-txGuard-address-address-bytes-}
Transaction guard for Velodrome V1 or V2 Pair


## Parameters:
- `_poolManagerLogic`: the pool manager logic

- `_to`: the liquidity pair address

- `_data`: the transaction data


## Return Values:
- txType the transaction type of a given transaction data

- isPublic if the transaction is public or private


