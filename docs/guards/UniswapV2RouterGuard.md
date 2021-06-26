## `UniswapV2RouterGuard`

Transaction guard for UniswapV2Router


This will be used for sushiswap as well since Sushi uses the same interface.


### `constructor(address _factory)` (public)





### `txGuard(address _poolManagerLogic, address, bytes data) → uint8 txType` (external)

Transaction guard for Uniswap V2


It supports exchange, addLiquidity and removeLiquidity functionalities



### `AddLiquidity(address fundAddress, address tokenA, address tokenB, address pair, uint256 time)`





### `RemoveLiquidity(address fundAddress, address tokenA, address tokenB, address pair, uint256 liquidity, uint256 time)`





