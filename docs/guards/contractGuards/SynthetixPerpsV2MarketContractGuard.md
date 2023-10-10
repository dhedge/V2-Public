

# Functions:
- [`constructor(address _susdProxy, address[] _whitelistedDHedgePools)`](#SynthetixPerpsV2MarketContractGuard-constructor-address-address---)
- [`txGuard(address _poolManagerLogic, address to, bytes data)`](#SynthetixPerpsV2MarketContractGuard-txGuard-address-address-bytes-)

# Events:
- [`PerpsV2MarketEvent(address fundAddress, address perpsV2Market)`](#SynthetixPerpsV2MarketContractGuard-PerpsV2MarketEvent-address-address-)


# Function `constructor(address _susdProxy, address[] _whitelistedDHedgePools)` {#SynthetixPerpsV2MarketContractGuard-constructor-address-address---}
No description




# Function `txGuard(address _poolManagerLogic, address to, bytes data) → uint16 txType, bool` {#SynthetixPerpsV2MarketContractGuard-txGuard-address-address-bytes-}
Transaction guard for a Synthetix PerpsV2 Market


## Parameters:
- `_poolManagerLogic`: the pool manager logic

- `to`: the PerpsV2 market

- `data`: the transaction data


## Return Values:
- txType the transaction type of a given transaction data.

- isPublic if the transaction is public or private




