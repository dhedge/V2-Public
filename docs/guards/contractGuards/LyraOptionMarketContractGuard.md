

# Functions:
- [`constructor(contract ILyraRegistry _lyraRegistry, address _nftTracker, uint256 _maxPositionCount)`](#LyraOptionMarketContractGuard-constructor-contract-ILyraRegistry-address-uint256-)
- [`txGuard(address _poolManagerLogic, address to, bytes data)`](#LyraOptionMarketContractGuard-txGuard-address-address-bytes-)
- [`afterTxGuard(address _poolManagerLogic, address to, bytes data)`](#LyraOptionMarketContractGuard-afterTxGuard-address-address-bytes-)

# Events:
- [`LyraOptionsMarketEvent(address fundAddress, address optionsMarket)`](#LyraOptionMarketContractGuard-LyraOptionsMarketEvent-address-address-)


# Function `constructor(contract ILyraRegistry _lyraRegistry, address _nftTracker, uint256 _maxPositionCount)` {#LyraOptionMarketContractGuard-constructor-contract-ILyraRegistry-address-uint256-}
No description




# Function `txGuard(address _poolManagerLogic, address to, bytes data) → uint16 txType, bool` {#LyraOptionMarketContractGuard-txGuard-address-address-bytes-}
Transaction guard for a Lyra Option Market


## Parameters:
- `_poolManagerLogic`: the pool manager logic

- `to`: the option market

- `data`: the transaction data


## Return Values:
- txType the transaction type of a given transaction data.

- isPublic if the transaction is public or private


# Function `afterTxGuard(address _poolManagerLogic, address to, bytes data)` {#LyraOptionMarketContractGuard-afterTxGuard-address-address-bytes-}
This function is called after execution transaction (used to track transactions)


## Parameters:
- `_poolManagerLogic`: the pool manager logic

- `data`: the transaction data



