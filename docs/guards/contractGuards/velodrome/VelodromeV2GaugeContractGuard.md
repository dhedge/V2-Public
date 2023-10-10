

# Functions:
- [`txGuard(address _poolManagerLogic, address _to, bytes _data)`](#VelodromeV2GaugeContractGuard-txGuard-address-address-bytes-)



# Function `txGuard(address _poolManagerLogic, address _to, bytes _data) → uint16 txType, bool` {#VelodromeV2GaugeContractGuard-txGuard-address-address-bytes-}
Transaction guard for Velodrome V2 Gauge


## Parameters:
- `_poolManagerLogic`: the pool manager logic

- `_to`: the gauge address

- `_data`: the transaction data


## Return Values:
- txType the transaction type of a given transaction data

- isPublic if the transaction is public or private


