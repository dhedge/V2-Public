This will be used for sushiswap as well since Sushi uses the same interface.

# Functions:
- [`constructor(address _factory)`](#UniswapV2RouterGuard-constructor-address-)
- [`txGuard(address _poolManagerLogic, address, bytes data)`](#UniswapV2RouterGuard-txGuard-address-address-bytes-)

# Events:
- [`AddLiquidity(address fundAddress, address tokenA, address tokenB, address pair, uint256 time)`](#UniswapV2RouterGuard-AddLiquidity-address-address-address-address-uint256-)
- [`RemoveLiquidity(address fundAddress, address tokenA, address tokenB, address pair, uint256 liquidity, uint256 time)`](#UniswapV2RouterGuard-RemoveLiquidity-address-address-address-address-uint256-uint256-)

# Function `constructor(address _factory)` {#UniswapV2RouterGuard-constructor-address-}
No description
# Function `txGuard(address _poolManagerLogic, address, bytes data) → uint8 txType` {#UniswapV2RouterGuard-txGuard-address-address-bytes-}
It supports exchange, addLiquidity and removeLiquidity functionalities

## Parameters:
- `_poolManagerLogic`: the pool manager logic

- `data`: the transaction data

## Return Values:
- txType the transaction type of a given transaction data. 2 for `Exchange` type, 3 for `Add Liquidity`, 4 for `Remove Liquidity`

# Event `AddLiquidity(address fundAddress, address tokenA, address tokenB, address pair, uint256 time)` {#UniswapV2RouterGuard-AddLiquidity-address-address-address-address-uint256-}
No description
# Event `RemoveLiquidity(address fundAddress, address tokenA, address tokenB, address pair, uint256 liquidity, uint256 time)` {#UniswapV2RouterGuard-RemoveLiquidity-address-address-address-address-uint256-uint256-}
No description
