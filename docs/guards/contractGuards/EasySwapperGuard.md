

# Functions:
- [`txGuard(address _poolManagerLogic, address easySwapper, bytes data)`](#EasySwapperGuard-txGuard-address-address-bytes-)

# Events:
- [`Deposit(address fundAddress, address depositAsset, uint256 time)`](#EasySwapperGuard-Deposit-address-address-uint256-)
- [`Withdraw(address fundAddress, address from, address withdrawalAsset, uint256 time)`](#EasySwapperGuard-Withdraw-address-address-address-uint256-)


# Function `txGuard(address _poolManagerLogic, address easySwapper, bytes data) → uint16 txType, bool` {#EasySwapperGuard-txGuard-address-address-bytes-}
Transaction guard for EasySwapper - used for Toros


## Parameters:
- `_poolManagerLogic`: the pool manager logic

- `data`: the transaction data


## Return Values:
- txType the transaction type of a given transaction data.

- isPublic if the transaction is public or private


