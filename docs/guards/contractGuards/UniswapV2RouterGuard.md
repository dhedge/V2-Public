Transaction guard for UniswapV2Router


# Functions:
- [`constructor(uint256 _slippageLimitNumerator, uint256 _slippageLimitDenominator)`](#UniswapV2RouterGuard-constructor-uint256-uint256-)
- [`txGuard(address _poolManagerLogic, address to, bytes data)`](#UniswapV2RouterGuard-txGuard-address-address-bytes-)

# Events:
- [`AddLiquidity(address fundAddress, address tokenA, address tokenB, address pair, uint256 amountADesired, uint256 amountBDesired, uint256 amountAMin, uint256 amountBMin, uint256 time)`](#UniswapV2RouterGuard-AddLiquidity-address-address-address-address-uint256-uint256-uint256-uint256-uint256-)
- [`RemoveLiquidity(address fundAddress, address tokenA, address tokenB, address pair, uint256 liquidity, uint256 amountAMin, uint256 amountBMin, uint256 time)`](#UniswapV2RouterGuard-RemoveLiquidity-address-address-address-address-uint256-uint256-uint256-uint256-)


# Function `constructor(uint256 _slippageLimitNumerator, uint256 _slippageLimitDenominator)` {#UniswapV2RouterGuard-constructor-uint256-uint256-}
No description




# Function `txGuard(address _poolManagerLogic, address to, bytes data) → uint16 txType, bool` {#UniswapV2RouterGuard-txGuard-address-address-bytes-}
Transaction guard for Uniswap V2


## Parameters:
- `_poolManagerLogic`: the pool manager logic

- `to`: the router address

- `data`: the transaction data


## Return Values:
- txType the transaction type of a given transaction data. 2 for `Exchange` type, 3 for `Add Liquidity`, 4 for `Remove Liquidity`

- isPublic if the transaction is public or private


