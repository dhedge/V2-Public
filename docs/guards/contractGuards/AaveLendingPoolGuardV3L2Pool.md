

# Functions:
- [`constructor(address _lendingPool)`](#AaveLendingPoolGuardV3L2Pool-constructor-address-)
- [`txGuard(address _poolManagerLogic, address to, bytes data)`](#AaveLendingPoolGuardV3L2Pool-txGuard-address-address-bytes-)



# Function `constructor(address _lendingPool)` {#AaveLendingPoolGuardV3L2Pool-constructor-address-}
No description




# Function `txGuard(address _poolManagerLogic, address to, bytes data) → uint16 txType, bool isPublic` {#AaveLendingPoolGuardV3L2Pool-txGuard-address-address-bytes-}
Transaction guard for Aave V3 L2 Lending Pool


## Parameters:
- `_poolManagerLogic`: the pool manager logic

- `data`: the transaction data


## Return Values:
- txType the transaction type of a given transaction data.

- isPublic if the transaction is public or private
















