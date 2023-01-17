

# Functions:
- [`constructor(uint256 _slippageLimitNumerator, uint256 _slippageLimitDenominator)`](#UniswapV3RouterGuard-constructor-uint256-uint256-)
- [`txGuard(address _poolManagerLogic, address to, bytes data)`](#UniswapV3RouterGuard-txGuard-address-address-bytes-)



# Function `constructor(uint256 _slippageLimitNumerator, uint256 _slippageLimitDenominator)` {#UniswapV3RouterGuard-constructor-uint256-uint256-}
No description




# Function `txGuard(address _poolManagerLogic, address to, bytes data) → uint16 txType, bool` {#UniswapV3RouterGuard-txGuard-address-address-bytes-}
Transaction guard for UniswavpV3SwapGuard


## Parameters:
- `_poolManagerLogic`: Pool address

- `data`: Transaction call data attempt by manager


## Return Values:
- txType transaction type described in PoolLogic

- isPublic if the transaction is public or private




