

# Functions:
- [`txGuard(address _poolManagerLogic, address, bytes _data)`](#PoolTokenSwapperGuard-txGuard-address-address-bytes-)



# Function `txGuard(address _poolManagerLogic, address, bytes _data) → uint16 txType, bool` {#PoolTokenSwapperGuard-txGuard-address-address-bytes-}
Allows dHEDGE pool managers to use swap to rebalance their portfolio


## Parameters:
- `_poolManagerLogic`: Pool manager logic address

- `_data`: Transaction data


## Return Values:
- txType Transaction type

- isPublic If the transaction is public or private


