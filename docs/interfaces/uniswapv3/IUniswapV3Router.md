Functions for swapping tokens via Uniswap V3

# Functions:
- [`exactInputSingle(struct IUniswapV3Router.ExactInputSingleParams params)`](#IUniswapV3Router-exactInputSingle-struct-IUniswapV3Router-ExactInputSingleParams-)
- [`exactInput(struct IUniswapV3Router.ExactInputParams params)`](#IUniswapV3Router-exactInput-struct-IUniswapV3Router-ExactInputParams-)



# Function `exactInputSingle(struct IUniswapV3Router.ExactInputSingleParams params) → uint256 amountOut` {#IUniswapV3Router-exactInputSingle-struct-IUniswapV3Router-ExactInputSingleParams-}
Swaps `amountIn` of one token for as much as possible of another token


## Parameters:
- `params`: The parameters necessary for the swap, encoded as `ExactInputSingleParams` in calldata


## Return Values:
- amountOut The amount of the received token


# Function `exactInput(struct IUniswapV3Router.ExactInputParams params) → uint256 amountOut` {#IUniswapV3Router-exactInput-struct-IUniswapV3Router-ExactInputParams-}
Swaps `amountIn` of one token for as much as possible of another along the specified path


## Parameters:
- `params`: The parameters necessary for the multi-hop swap, encoded as `ExactInputParams` in calldata


## Return Values:
- amountOut The amount of the received token


