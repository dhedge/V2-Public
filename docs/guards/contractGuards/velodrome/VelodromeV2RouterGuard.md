

# Functions:
- [`txGuard(address _poolManagerLogic, address _to, bytes _data)`](#VelodromeV2RouterGuard-txGuard-address-address-bytes-)

# Events:
- [`AddLiquidity(address fundAddress, address pair, bytes params, uint256 time)`](#VelodromeV2RouterGuard-AddLiquidity-address-address-bytes-uint256-)
- [`RemoveLiquidity(address fundAddress, address pair, bytes params, uint256 time)`](#VelodromeV2RouterGuard-RemoveLiquidity-address-address-bytes-uint256-)


# Function `txGuard(address _poolManagerLogic, address _to, bytes _data) → uint16 txType, bool` {#VelodromeV2RouterGuard-txGuard-address-address-bytes-}
Transaction guard for Velodrome V2 Router


## Parameters:
- `_poolManagerLogic`: the pool manager logic

- `_to`: the router address

- `_data`: the transaction data


## Return Values:
- txType the transaction type of a given transaction data

- isPublic if the transaction is public or private


