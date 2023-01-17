

# Functions:
- [`constructor(contract ILyraRegistry _lyraRegistry, address _nftTracker, uint256 _maxPositionCount)`](#LyraOptionMarketWrapperContractGuardRollups-constructor-contract-ILyraRegistry-address-uint256-)
- [`txGuard(address _poolManagerLogic, address to, bytes data)`](#LyraOptionMarketWrapperContractGuardRollups-txGuard-address-address-bytes-)
- [`afterTxGuard(address _poolManagerLogic, address to, bytes data)`](#LyraOptionMarketWrapperContractGuardRollups-afterTxGuard-address-address-bytes-)



# Function `constructor(contract ILyraRegistry _lyraRegistry, address _nftTracker, uint256 _maxPositionCount)` {#LyraOptionMarketWrapperContractGuardRollups-constructor-contract-ILyraRegistry-address-uint256-}
No description




# Function `txGuard(address _poolManagerLogic, address to, bytes data) → uint16 txType, bool isPublic` {#LyraOptionMarketWrapperContractGuardRollups-txGuard-address-address-bytes-}
Transaction guard for OptionMarketWrapper - used for Toros


## Parameters:
- `_poolManagerLogic`: the pool manager logic

- `data`: the transaction data


## Return Values:
- txType the transaction type of a given transaction data.

- isPublic if the transaction is public or private


# Function `afterTxGuard(address _poolManagerLogic, address to, bytes data)` {#LyraOptionMarketWrapperContractGuardRollups-afterTxGuard-address-address-bytes-}
This function is called after execution transaction (used to track transactions)


## Parameters:
- `_poolManagerLogic`: the pool manager logic

- `data`: the transaction data



















