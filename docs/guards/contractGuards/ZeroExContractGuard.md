

# Functions:
- [`constructor(address _slippageAccumulator)`](#ZeroExContractGuard-constructor-address-)
- [`txGuard(address _poolManagerLogic, address _to, bytes _data)`](#ZeroExContractGuard-txGuard-address-address-bytes-)



# Function `constructor(address _slippageAccumulator)` {#ZeroExContractGuard-constructor-address-}
No description




# Function `txGuard(address _poolManagerLogic, address _to, bytes _data) → uint16 txType, bool` {#ZeroExContractGuard-txGuard-address-address-bytes-}
Transaction guard for ZeroEx protocol swaps


## Parameters:
- `_poolManagerLogic`: The pool manager logic address

- `_to`: Transaction target address

- `_data`: Transaction call data attempt by manager


## Return Values:
- txType Transaction type described in PoolLogic

- isPublic If the transaction is public or private


