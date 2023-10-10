Transaction guard for Velodrome Router

# Functions:
- [`txGuard(address _poolManagerLogic, address to, bytes data)`](#VelodromeRouterGuard-txGuard-address-address-bytes-)

# Events:
- [`AddLiquidity(address fundAddress, address pair, bytes params, uint256 time)`](#VelodromeRouterGuard-AddLiquidity-address-address-bytes-uint256-)
- [`RemoveLiquidity(address fundAddress, address pair, bytes params, uint256 time)`](#VelodromeRouterGuard-RemoveLiquidity-address-address-bytes-uint256-)


# Function `txGuard(address _poolManagerLogic, address to, bytes data) → uint16 txType, bool` {#VelodromeRouterGuard-txGuard-address-address-bytes-}
Transaction guard for Velodrome


## Parameters:
- `_poolManagerLogic`: the pool manager logic

- `to`: the router address

- `data`: the transaction data


## Return Values:
- txType the transaction type of a given transaction data. 2 for `Exchange` type, 3 for `Add Liquidity`, 4 for `Remove Liquidity`

- isPublic if the transaction is public or private


