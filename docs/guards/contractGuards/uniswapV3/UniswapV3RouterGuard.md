

# Functions:
- [`constructor(address _slippageAccumulator)`](#UniswapV3RouterGuard-constructor-address-)
- [`txGuard(address _poolManagerLogic, address to, bytes data)`](#UniswapV3RouterGuard-txGuard-address-address-bytes-)



# Function `constructor(address _slippageAccumulator)` {#UniswapV3RouterGuard-constructor-address-}
No description




# Function `txGuard(address _poolManagerLogic, address to, bytes data) → uint16 txType, bool` {#UniswapV3RouterGuard-txGuard-address-address-bytes-}
Transaction guard for UniswavpV3SwapGuard


## Parameters:
- `_poolManagerLogic`: Pool address

- `data`: Transaction call data attempt by manager


## Return Values:
- txType transaction type described in PoolLogic

- isPublic if the transaction is public or private




