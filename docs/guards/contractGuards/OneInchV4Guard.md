Transaction guard for OneInchV3Router

# Functions:
- [`constructor(address _slippageAccumulator)`](#OneInchV4Guard-constructor-address-)
- [`txGuard(address _poolManagerLogic, address to, bytes data)`](#OneInchV4Guard-txGuard-address-address-bytes-)



# Function `constructor(address _slippageAccumulator)` {#OneInchV4Guard-constructor-address-}
No description




# Function `txGuard(address _poolManagerLogic, address to, bytes data) → uint16 txType, bool` {#OneInchV4Guard-txGuard-address-address-bytes-}
Transaction guard for OneInchV3


## Parameters:
- `_poolManagerLogic`: the pool manager logic

- `data`: the transaction data


## Return Values:
- txType the transaction type of a given transaction data. 2 for `Exchange` type

- isPublic if the transaction is public or private




