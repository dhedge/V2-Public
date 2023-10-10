

# Functions:
- [`txGuard(address _poolManagerLogic, address to, bytes data)`](#StargateRouterContractGuard-txGuard-address-address-bytes-)



# Function `txGuard(address _poolManagerLogic, address to, bytes data) → uint16 txType, bool` {#StargateRouterContractGuard-txGuard-address-address-bytes-}
Transaction guard for the Stargate router


## Parameters:
- `_poolManagerLogic`: the pool manager logic

- `data`: the transaction data


## Return Values:
- txType the transaction type of a given transaction data.

- isPublic if the transaction is public or private


