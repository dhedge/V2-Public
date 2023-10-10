

# Functions:
- [`constructor(contract ILyraRegistry _lyraRegistry, address _nftTracker, uint256 _maxPositionCount)`](#LyraOptionMarketWrapperContractGuard-constructor-contract-ILyraRegistry-address-uint256-)
- [`marketViewer()`](#LyraOptionMarketWrapperContractGuard-marketViewer--)
- [`marketWrapper()`](#LyraOptionMarketWrapperContractGuard-marketWrapper--)
- [`getOptionPositions(address poolLogic)`](#LyraOptionMarketWrapperContractGuard-getOptionPositions-address-)
- [`txGuard(address _poolManagerLogic, address to, bytes data)`](#LyraOptionMarketWrapperContractGuard-txGuard-address-address-bytes-)
- [`afterTxGuard(address _poolManagerLogic, address to, bytes data)`](#LyraOptionMarketWrapperContractGuard-afterTxGuard-address-address-bytes-)
- [`removeClosedPosition(address poolLogic, address optionMarket, uint256 positionId)`](#LyraOptionMarketWrapperContractGuard-removeClosedPosition-address-address-uint256-)
- [`settleExpiredAndFilterActivePositions(address poolLogic)`](#LyraOptionMarketWrapperContractGuard-settleExpiredAndFilterActivePositions-address-)
- [`settleExpiredAndFilterActivePositions(address poolLogic, address guardedContract)`](#LyraOptionMarketWrapperContractGuard-settleExpiredAndFilterActivePositions-address-address-)



# Function `constructor(contract ILyraRegistry _lyraRegistry, address _nftTracker, uint256 _maxPositionCount)` {#LyraOptionMarketWrapperContractGuard-constructor-contract-ILyraRegistry-address-uint256-}
No description




# Function `marketViewer() → contract IOptionMarketViewer` {#LyraOptionMarketWrapperContractGuard-marketViewer--}
No description




# Function `marketWrapper() → address` {#LyraOptionMarketWrapperContractGuard-marketWrapper--}
No description




# Function `getOptionPositions(address poolLogic) → struct LyraOptionMarketWrapperContractGuard.OptionPosition[] optionPositions` {#LyraOptionMarketWrapperContractGuard-getOptionPositions-address-}
No description




# Function `txGuard(address _poolManagerLogic, address to, bytes data) → uint16 txType, bool` {#LyraOptionMarketWrapperContractGuard-txGuard-address-address-bytes-}
Transaction guard for OptionMarketWrapper - used for Toros


## Parameters:
- `_poolManagerLogic`: the pool manager logic

- `data`: the transaction data


## Return Values:
- txType the transaction type of a given transaction data.

- isPublic if the transaction is public or private




# Function `afterTxGuard(address _poolManagerLogic, address to, bytes data)` {#LyraOptionMarketWrapperContractGuard-afterTxGuard-address-address-bytes-}
This function is called after execution transaction (used to track transactions)


## Parameters:
- `_poolManagerLogic`: the pool manager logic

- `data`: the transaction data





# Function `removeClosedPosition(address poolLogic, address optionMarket, uint256 positionId)` {#LyraOptionMarketWrapperContractGuard-removeClosedPosition-address-address-uint256-}
No description




# Function `settleExpiredAndFilterActivePositions(address poolLogic)` {#LyraOptionMarketWrapperContractGuard-settleExpiredAndFilterActivePositions-address-}
Function for settling expired options and filtering active options





# Function `settleExpiredAndFilterActivePositions(address poolLogic, address guardedContract)` {#LyraOptionMarketWrapperContractGuard-settleExpiredAndFilterActivePositions-address-address-}
Public function for settling expired options and filtering active options







