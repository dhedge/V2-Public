Functions for swapping tokens via Uniswap V3

# Functions:
- [`exactInputSingle(struct IV3SwapRouter.ExactInputSingleParams params)`](#IV3SwapRouter-exactInputSingle-struct-IV3SwapRouter-ExactInputSingleParams-)
- [`exactInput(struct IV3SwapRouter.ExactInputParams params)`](#IV3SwapRouter-exactInput-struct-IV3SwapRouter-ExactInputParams-)
- [`exactOutputSingle(struct IV3SwapRouter.ExactOutputSingleParams params)`](#IV3SwapRouter-exactOutputSingle-struct-IV3SwapRouter-ExactOutputSingleParams-)
- [`exactOutput(struct IV3SwapRouter.ExactOutputParams params)`](#IV3SwapRouter-exactOutput-struct-IV3SwapRouter-ExactOutputParams-)



# Function `exactInputSingle(struct IV3SwapRouter.ExactInputSingleParams params) → uint256 amountOut` {#IV3SwapRouter-exactInputSingle-struct-IV3SwapRouter-ExactInputSingleParams-}
Swaps `amountIn` of one token for as much as possible of another token


## Parameters:
- `params`: The parameters necessary for the swap, encoded as `ExactInputSingleParams` in calldata


## Return Values:
- amountOut The amount of the received token


# Function `exactInput(struct IV3SwapRouter.ExactInputParams params) → uint256 amountOut` {#IV3SwapRouter-exactInput-struct-IV3SwapRouter-ExactInputParams-}
Swaps `amountIn` of one token for as much as possible of another along the specified path


## Parameters:
- `params`: The parameters necessary for the multi-hop swap, encoded as `ExactInputParams` in calldata


## Return Values:
- amountOut The amount of the received token


# Function `exactOutputSingle(struct IV3SwapRouter.ExactOutputSingleParams params) → uint256 amountIn` {#IV3SwapRouter-exactOutputSingle-struct-IV3SwapRouter-ExactOutputSingleParams-}
Swaps as little as possible of one token for `amountOut` of another token
that may remain in the router after the swap.


## Parameters:
- `params`: The parameters necessary for the swap, encoded as `ExactOutputSingleParams` in calldata


## Return Values:
- amountIn The amount of the input token


# Function `exactOutput(struct IV3SwapRouter.ExactOutputParams params) → uint256 amountIn` {#IV3SwapRouter-exactOutput-struct-IV3SwapRouter-ExactOutputParams-}
Swaps as little as possible of one token for `amountOut` of another along the specified path (reversed)
that may remain in the router after the swap.


## Parameters:
- `params`: The parameters necessary for the multi-hop swap, encoded as `ExactOutputParams` in calldata


## Return Values:
- amountIn The amount of the input token


