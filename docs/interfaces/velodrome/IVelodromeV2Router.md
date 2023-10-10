

# Functions:
- [`defaultFactory()`](#IVelodromeV2Router-defaultFactory--)
- [`sortTokens(address tokenA, address tokenB)`](#IVelodromeV2Router-sortTokens-address-address-)
- [`poolFor(address tokenA, address tokenB, bool stable, address _factory)`](#IVelodromeV2Router-poolFor-address-address-bool-address-)
- [`pairFor(address tokenA, address tokenB, bool stable, address _factory)`](#IVelodromeV2Router-pairFor-address-address-bool-address-)
- [`getReserves(address tokenA, address tokenB, bool stable, address _factory)`](#IVelodromeV2Router-getReserves-address-address-bool-address-)
- [`getAmountsOut(uint256 amountIn, struct IVelodromeV2Router.Route[] routes)`](#IVelodromeV2Router-getAmountsOut-uint256-struct-IVelodromeV2Router-Route---)
- [`quoteAddLiquidity(address tokenA, address tokenB, bool stable, address _factory, uint256 amountADesired, uint256 amountBDesired)`](#IVelodromeV2Router-quoteAddLiquidity-address-address-bool-address-uint256-uint256-)
- [`quoteRemoveLiquidity(address tokenA, address tokenB, bool stable, address _factory, uint256 liquidity)`](#IVelodromeV2Router-quoteRemoveLiquidity-address-address-bool-address-uint256-)
- [`addLiquidity(address tokenA, address tokenB, bool stable, uint256 amountADesired, uint256 amountBDesired, uint256 amountAMin, uint256 amountBMin, address to, uint256 deadline)`](#IVelodromeV2Router-addLiquidity-address-address-bool-uint256-uint256-uint256-uint256-address-uint256-)
- [`addLiquidityETH(address token, bool stable, uint256 amountTokenDesired, uint256 amountTokenMin, uint256 amountETHMin, address to, uint256 deadline)`](#IVelodromeV2Router-addLiquidityETH-address-bool-uint256-uint256-uint256-address-uint256-)
- [`removeLiquidity(address tokenA, address tokenB, bool stable, uint256 liquidity, uint256 amountAMin, uint256 amountBMin, address to, uint256 deadline)`](#IVelodromeV2Router-removeLiquidity-address-address-bool-uint256-uint256-uint256-address-uint256-)
- [`removeLiquidityETH(address token, bool stable, uint256 liquidity, uint256 amountTokenMin, uint256 amountETHMin, address to, uint256 deadline)`](#IVelodromeV2Router-removeLiquidityETH-address-bool-uint256-uint256-uint256-address-uint256-)
- [`removeLiquidityETHSupportingFeeOnTransferTokens(address token, bool stable, uint256 liquidity, uint256 amountTokenMin, uint256 amountETHMin, address to, uint256 deadline)`](#IVelodromeV2Router-removeLiquidityETHSupportingFeeOnTransferTokens-address-bool-uint256-uint256-uint256-address-uint256-)
- [`swapExactTokensForTokens(uint256 amountIn, uint256 amountOutMin, struct IVelodromeV2Router.Route[] routes, address to, uint256 deadline)`](#IVelodromeV2Router-swapExactTokensForTokens-uint256-uint256-struct-IVelodromeV2Router-Route---address-uint256-)
- [`swapExactETHForTokens(uint256 amountOutMin, struct IVelodromeV2Router.Route[] routes, address to, uint256 deadline)`](#IVelodromeV2Router-swapExactETHForTokens-uint256-struct-IVelodromeV2Router-Route---address-uint256-)
- [`swapExactTokensForETH(uint256 amountIn, uint256 amountOutMin, struct IVelodromeV2Router.Route[] routes, address to, uint256 deadline)`](#IVelodromeV2Router-swapExactTokensForETH-uint256-uint256-struct-IVelodromeV2Router-Route---address-uint256-)
- [`swapExactTokensForTokensSupportingFeeOnTransferTokens(uint256 amountIn, uint256 amountOutMin, struct IVelodromeV2Router.Route[] routes, address to, uint256 deadline)`](#IVelodromeV2Router-swapExactTokensForTokensSupportingFeeOnTransferTokens-uint256-uint256-struct-IVelodromeV2Router-Route---address-uint256-)
- [`swapExactETHForTokensSupportingFeeOnTransferTokens(uint256 amountOutMin, struct IVelodromeV2Router.Route[] routes, address to, uint256 deadline)`](#IVelodromeV2Router-swapExactETHForTokensSupportingFeeOnTransferTokens-uint256-struct-IVelodromeV2Router-Route---address-uint256-)
- [`swapExactTokensForETHSupportingFeeOnTransferTokens(uint256 amountIn, uint256 amountOutMin, struct IVelodromeV2Router.Route[] routes, address to, uint256 deadline)`](#IVelodromeV2Router-swapExactTokensForETHSupportingFeeOnTransferTokens-uint256-uint256-struct-IVelodromeV2Router-Route---address-uint256-)
- [`zapIn(address tokenIn, uint256 amountInA, uint256 amountInB, struct IVelodromeV2Router.Zap zapInPool, struct IVelodromeV2Router.Route[] routesA, struct IVelodromeV2Router.Route[] routesB, address to, bool stake)`](#IVelodromeV2Router-zapIn-address-uint256-uint256-struct-IVelodromeV2Router-Zap-struct-IVelodromeV2Router-Route---struct-IVelodromeV2Router-Route---address-bool-)
- [`zapOut(address tokenOut, uint256 liquidity, struct IVelodromeV2Router.Zap zapOutPool, struct IVelodromeV2Router.Route[] routesA, struct IVelodromeV2Router.Route[] routesB)`](#IVelodromeV2Router-zapOut-address-uint256-struct-IVelodromeV2Router-Zap-struct-IVelodromeV2Router-Route---struct-IVelodromeV2Router-Route---)
- [`generateZapInParams(address tokenA, address tokenB, bool stable, address _factory, uint256 amountInA, uint256 amountInB, struct IVelodromeV2Router.Route[] routesA, struct IVelodromeV2Router.Route[] routesB)`](#IVelodromeV2Router-generateZapInParams-address-address-bool-address-uint256-uint256-struct-IVelodromeV2Router-Route---struct-IVelodromeV2Router-Route---)
- [`generateZapOutParams(address tokenA, address tokenB, bool stable, address _factory, uint256 liquidity, struct IVelodromeV2Router.Route[] routesA, struct IVelodromeV2Router.Route[] routesB)`](#IVelodromeV2Router-generateZapOutParams-address-address-bool-address-uint256-struct-IVelodromeV2Router-Route---struct-IVelodromeV2Router-Route---)
- [`quoteStableLiquidityRatio(address tokenA, address tokenB, address factory)`](#IVelodromeV2Router-quoteStableLiquidityRatio-address-address-address-)



# Function `defaultFactory() → address` {#IVelodromeV2Router-defaultFactory--}
No description




# Function `sortTokens(address tokenA, address tokenB) → address token0, address token1` {#IVelodromeV2Router-sortTokens-address-address-}
Sort two tokens by which address value is less than the other


## Parameters:
- `tokenA`:   Address of token to sort

- `tokenB`:   Address of token to sort


## Return Values:
- token0  Lower address value between tokenA and tokenB

- token1  Higher address value between tokenA and tokenB


# Function `poolFor(address tokenA, address tokenB, bool stable, address _factory) → address pool` {#IVelodromeV2Router-poolFor-address-address-bool-address-}
Calculate the address of a pool by its' factory.
        Used by all Router functions containing a `Route[]` or `_factory` argument.
        Reverts if _factory is not approved by the FactoryRegistry


## Parameters:
- `tokenA`:   Address of token to query

- `tokenB`:   Address of token to query

- `stable`:   True if pool is stable, false if volatile

- `_factory`: Address of factory which created the pool



# Function `pairFor(address tokenA, address tokenB, bool stable, address _factory) → address pool` {#IVelodromeV2Router-pairFor-address-address-bool-address-}
Wraps around poolFor(tokenA,tokenB,stable,_factory) for backwards compatibility to Velodrome v1




# Function `getReserves(address tokenA, address tokenB, bool stable, address _factory) → uint256 reserveA, uint256 reserveB` {#IVelodromeV2Router-getReserves-address-address-bool-address-}
Fetch and sort the reserves for a pool


## Parameters:
- `tokenA`:       .

- `tokenB`:       .

- `stable`:       True if pool is stable, false if volatile

- `_factory`:     Address of PoolFactory for tokenA and tokenB


## Return Values:
- reserveA    Amount of reserves of the sorted token A

- reserveB    Amount of reserves of the sorted token B


# Function `getAmountsOut(uint256 amountIn, struct IVelodromeV2Router.Route[] routes) → uint256[] amounts` {#IVelodromeV2Router-getAmountsOut-uint256-struct-IVelodromeV2Router-Route---}
Perform chained getAmountOut calculations on any number of pools




# Function `quoteAddLiquidity(address tokenA, address tokenB, bool stable, address _factory, uint256 amountADesired, uint256 amountBDesired) → uint256 amountA, uint256 amountB, uint256 liquidity` {#IVelodromeV2Router-quoteAddLiquidity-address-address-bool-address-uint256-uint256-}
Quote the amount deposited into a Pool


## Parameters:
- `tokenA`:           .

- `tokenB`:           .

- `stable`:           True if pool is stable, false if volatile

- `_factory`:         Address of PoolFactory for tokenA and tokenB

- `amountADesired`:   Amount of tokenA desired to deposit

- `amountBDesired`:   Amount of tokenB desired to deposit


## Return Values:
- amountA         Amount of tokenA to actually deposit

- amountB         Amount of tokenB to actually deposit

- liquidity       Amount of liquidity token returned from deposit


# Function `quoteRemoveLiquidity(address tokenA, address tokenB, bool stable, address _factory, uint256 liquidity) → uint256 amountA, uint256 amountB` {#IVelodromeV2Router-quoteRemoveLiquidity-address-address-bool-address-uint256-}
Quote the amount of liquidity removed from a Pool


## Parameters:
- `tokenA`:       .

- `tokenB`:       .

- `stable`:       True if pool is stable, false if volatile

- `_factory`:     Address of PoolFactory for tokenA and tokenB

- `liquidity`:    Amount of liquidity to remove


## Return Values:
- amountA     Amount of tokenA received

- amountB     Amount of tokenB received


# Function `addLiquidity(address tokenA, address tokenB, bool stable, uint256 amountADesired, uint256 amountBDesired, uint256 amountAMin, uint256 amountBMin, address to, uint256 deadline) → uint256 amountA, uint256 amountB, uint256 liquidity` {#IVelodromeV2Router-addLiquidity-address-address-bool-uint256-uint256-uint256-uint256-address-uint256-}
Add liquidity of two tokens to a Pool


## Parameters:
- `tokenA`:           .

- `tokenB`:           .

- `stable`:           True if pool is stable, false if volatile

- `amountADesired`:   Amount of tokenA desired to deposit

- `amountBDesired`:   Amount of tokenB desired to deposit

- `amountAMin`:       Minimum amount of tokenA to deposit

- `amountBMin`:       Minimum amount of tokenB to deposit

- `to`:               Recipient of liquidity token

- `deadline`:         Deadline to receive liquidity


## Return Values:
- amountA         Amount of tokenA to actually deposit

- amountB         Amount of tokenB to actually deposit

- liquidity       Amount of liquidity token returned from deposit


# Function `addLiquidityETH(address token, bool stable, uint256 amountTokenDesired, uint256 amountTokenMin, uint256 amountETHMin, address to, uint256 deadline) → uint256 amountToken, uint256 amountETH, uint256 liquidity` {#IVelodromeV2Router-addLiquidityETH-address-bool-uint256-uint256-uint256-address-uint256-}
Add liquidity of a token and WETH (transferred as ETH) to a Pool


## Parameters:
- `token`:                .

- `stable`:               True if pool is stable, false if volatile

- `amountTokenDesired`:   Amount of token desired to deposit

- `amountTokenMin`:       Minimum amount of token to deposit

- `amountETHMin`:         Minimum amount of ETH to deposit

- `to`:                   Recipient of liquidity token

- `deadline`:             Deadline to add liquidity


## Return Values:
- amountToken         Amount of token to actually deposit

- amountETH           Amount of tokenETH to actually deposit

- liquidity           Amount of liquidity token returned from deposit


# Function `removeLiquidity(address tokenA, address tokenB, bool stable, uint256 liquidity, uint256 amountAMin, uint256 amountBMin, address to, uint256 deadline) → uint256 amountA, uint256 amountB` {#IVelodromeV2Router-removeLiquidity-address-address-bool-uint256-uint256-uint256-address-uint256-}
Remove liquidity of two tokens from a Pool


## Parameters:
- `tokenA`:       .

- `tokenB`:       .

- `stable`:       True if pool is stable, false if volatile

- `liquidity`:    Amount of liquidity to remove

- `amountAMin`:   Minimum amount of tokenA to receive

- `amountBMin`:   Minimum amount of tokenB to receive

- `to`:           Recipient of tokens received

- `deadline`:     Deadline to remove liquidity


## Return Values:
- amountA     Amount of tokenA received

- amountB     Amount of tokenB received


# Function `removeLiquidityETH(address token, bool stable, uint256 liquidity, uint256 amountTokenMin, uint256 amountETHMin, address to, uint256 deadline) → uint256 amountToken, uint256 amountETH` {#IVelodromeV2Router-removeLiquidityETH-address-bool-uint256-uint256-uint256-address-uint256-}
Remove liquidity of a token and WETH (returned as ETH) from a Pool


## Parameters:
- `token`:            .

- `stable`:           True if pool is stable, false if volatile

- `liquidity`:        Amount of liquidity to remove

- `amountTokenMin`:   Minimum amount of token to receive

- `amountETHMin`:     Minimum amount of ETH to receive

- `to`:               Recipient of liquidity token

- `deadline`:         Deadline to receive liquidity


## Return Values:
- amountToken     Amount of token received

- amountETH       Amount of ETH received


# Function `removeLiquidityETHSupportingFeeOnTransferTokens(address token, bool stable, uint256 liquidity, uint256 amountTokenMin, uint256 amountETHMin, address to, uint256 deadline) → uint256 amountETH` {#IVelodromeV2Router-removeLiquidityETHSupportingFeeOnTransferTokens-address-bool-uint256-uint256-uint256-address-uint256-}
Remove liquidity of a fee-on-transfer token and WETH (returned as ETH) from a Pool


## Parameters:
- `token`:            .

- `stable`:           True if pool is stable, false if volatile

- `liquidity`:        Amount of liquidity to remove

- `amountTokenMin`:   Minimum amount of token to receive

- `amountETHMin`:     Minimum amount of ETH to receive

- `to`:               Recipient of liquidity token

- `deadline`:         Deadline to receive liquidity


## Return Values:
- amountETH       Amount of ETH received


# Function `swapExactTokensForTokens(uint256 amountIn, uint256 amountOutMin, struct IVelodromeV2Router.Route[] routes, address to, uint256 deadline) → uint256[] amounts` {#IVelodromeV2Router-swapExactTokensForTokens-uint256-uint256-struct-IVelodromeV2Router-Route---address-uint256-}
Swap one token for another


## Parameters:
- `amountIn`:     Amount of token in

- `amountOutMin`: Minimum amount of desired token received

- `routes`:       Array of trade routes used in the swap

- `to`:           Recipient of the tokens received

- `deadline`:     Deadline to receive tokens


## Return Values:
- amounts     Array of amounts returned per route


# Function `swapExactETHForTokens(uint256 amountOutMin, struct IVelodromeV2Router.Route[] routes, address to, uint256 deadline) → uint256[] amounts` {#IVelodromeV2Router-swapExactETHForTokens-uint256-struct-IVelodromeV2Router-Route---address-uint256-}
Swap ETH for a token


## Parameters:
- `amountOutMin`: Minimum amount of desired token received

- `routes`:       Array of trade routes used in the swap

- `to`:           Recipient of the tokens received

- `deadline`:     Deadline to receive tokens


## Return Values:
- amounts     Array of amounts returned per route


# Function `swapExactTokensForETH(uint256 amountIn, uint256 amountOutMin, struct IVelodromeV2Router.Route[] routes, address to, uint256 deadline) → uint256[] amounts` {#IVelodromeV2Router-swapExactTokensForETH-uint256-uint256-struct-IVelodromeV2Router-Route---address-uint256-}
Swap a token for WETH (returned as ETH)


## Parameters:
- `amountIn`:     Amount of token in

- `amountOutMin`: Minimum amount of desired ETH

- `routes`:       Array of trade routes used in the swap

- `to`:           Recipient of the tokens received

- `deadline`:     Deadline to receive tokens


## Return Values:
- amounts     Array of amounts returned per route


# Function `swapExactTokensForTokensSupportingFeeOnTransferTokens(uint256 amountIn, uint256 amountOutMin, struct IVelodromeV2Router.Route[] routes, address to, uint256 deadline)` {#IVelodromeV2Router-swapExactTokensForTokensSupportingFeeOnTransferTokens-uint256-uint256-struct-IVelodromeV2Router-Route---address-uint256-}
Swap one token for another supporting fee-on-transfer tokens


## Parameters:
- `amountIn`:     Amount of token in

- `amountOutMin`: Minimum amount of desired token received

- `routes`:       Array of trade routes used in the swap

- `to`:           Recipient of the tokens received

- `deadline`:     Deadline to receive tokens



# Function `swapExactETHForTokensSupportingFeeOnTransferTokens(uint256 amountOutMin, struct IVelodromeV2Router.Route[] routes, address to, uint256 deadline)` {#IVelodromeV2Router-swapExactETHForTokensSupportingFeeOnTransferTokens-uint256-struct-IVelodromeV2Router-Route---address-uint256-}
Swap ETH for a token supporting fee-on-transfer tokens


## Parameters:
- `amountOutMin`: Minimum amount of desired token received

- `routes`:       Array of trade routes used in the swap

- `to`:           Recipient of the tokens received

- `deadline`:     Deadline to receive tokens



# Function `swapExactTokensForETHSupportingFeeOnTransferTokens(uint256 amountIn, uint256 amountOutMin, struct IVelodromeV2Router.Route[] routes, address to, uint256 deadline)` {#IVelodromeV2Router-swapExactTokensForETHSupportingFeeOnTransferTokens-uint256-uint256-struct-IVelodromeV2Router-Route---address-uint256-}
Swap a token for WETH (returned as ETH) supporting fee-on-transfer tokens


## Parameters:
- `amountIn`:     Amount of token in

- `amountOutMin`: Minimum amount of desired ETH

- `routes`:       Array of trade routes used in the swap

- `to`:           Recipient of the tokens received

- `deadline`:     Deadline to receive tokens



# Function `zapIn(address tokenIn, uint256 amountInA, uint256 amountInB, struct IVelodromeV2Router.Zap zapInPool, struct IVelodromeV2Router.Route[] routesA, struct IVelodromeV2Router.Route[] routesB, address to, bool stake) → uint256 liquidity` {#IVelodromeV2Router-zapIn-address-uint256-uint256-struct-IVelodromeV2Router-Zap-struct-IVelodromeV2Router-Route---struct-IVelodromeV2Router-Route---address-bool-}
Zap a token A into a pool (B, C). (A can be equal to B or C).
        Supports standard ERC20 tokens only (i.e. not fee-on-transfer tokens etc).
        Slippage is required for the initial swap.
        Additional slippage may be required when adding liquidity as the
        price of the token may have changed.


## Parameters:
- `tokenIn`:      Token you are zapping in from (i.e. input token).

- `amountInA`:    Amount of input token you wish to send down routesA

- `amountInB`:    Amount of input token you wish to send down routesB

- `zapInPool`:    Contains zap struct information. See Zap struct.

- `routesA`:      Route used to convert input token to tokenA

- `routesB`:      Route used to convert input token to tokenB

- `to`:           Address you wish to mint liquidity to.

- `stake`:        Auto-stake liquidity in corresponding gauge.


## Return Values:
- liquidity   Amount of LP tokens created from zapping in.


# Function `zapOut(address tokenOut, uint256 liquidity, struct IVelodromeV2Router.Zap zapOutPool, struct IVelodromeV2Router.Route[] routesA, struct IVelodromeV2Router.Route[] routesB)` {#IVelodromeV2Router-zapOut-address-uint256-struct-IVelodromeV2Router-Zap-struct-IVelodromeV2Router-Route---struct-IVelodromeV2Router-Route---}
Zap out a pool (B, C) into A.
        Supports standard ERC20 tokens only (i.e. not fee-on-transfer tokens etc).
        Slippage is required for the removal of liquidity.
        Additional slippage may be required on the swap as the
        price of the token may have changed.


## Parameters:
- `tokenOut`:     Token you are zapping out to (i.e. output token).

- `liquidity`:    Amount of liquidity you wish to remove.

- `zapOutPool`:   Contains zap struct information. See Zap struct.

- `routesA`:      Route used to convert tokenA into output token.

- `routesB`:      Route used to convert tokenB into output token.



# Function `generateZapInParams(address tokenA, address tokenB, bool stable, address _factory, uint256 amountInA, uint256 amountInB, struct IVelodromeV2Router.Route[] routesA, struct IVelodromeV2Router.Route[] routesB) → uint256 amountOutMinA, uint256 amountOutMinB, uint256 amountAMin, uint256 amountBMin` {#IVelodromeV2Router-generateZapInParams-address-address-bool-address-uint256-uint256-struct-IVelodromeV2Router-Route---struct-IVelodromeV2Router-Route---}
Used to generate params required for zapping in.
        Zap in => remove liquidity then swap.
        Apply slippage to expected swap values to account for changes in reserves in between.


## Parameters:
- `tokenA`:           .

- `tokenB`:           .

- `stable`:           .

- `_factory`:         .

- `amountInA`:        Amount of input token you wish to send down routesA

- `amountInB`:        Amount of input token you wish to send down routesB

- `routesA`:          Route used to convert input token to tokenA

- `routesB`:          Route used to convert input token to tokenB


## Return Values:
- amountOutMinA   Minimum output expected from swapping input token to tokenA.

- amountOutMinB   Minimum output expected from swapping input token to tokenB.

- amountAMin      Minimum amount of tokenA expected from depositing liquidity.

- amountBMin      Minimum amount of tokenB expected from depositing liquidity.


# Function `generateZapOutParams(address tokenA, address tokenB, bool stable, address _factory, uint256 liquidity, struct IVelodromeV2Router.Route[] routesA, struct IVelodromeV2Router.Route[] routesB) → uint256 amountOutMinA, uint256 amountOutMinB, uint256 amountAMin, uint256 amountBMin` {#IVelodromeV2Router-generateZapOutParams-address-address-bool-address-uint256-struct-IVelodromeV2Router-Route---struct-IVelodromeV2Router-Route---}
Used to generate params required for zapping out.
        Zap out => swap then add liquidity.
        Apply slippage to expected liquidity values to account for changes in reserves in between.


## Parameters:
- `tokenA`:           .

- `tokenB`:           .

- `stable`:           .

- `_factory`:         .

- `liquidity`:        Amount of liquidity being zapped out of into a given output token.

- `routesA`:          Route used to convert tokenA into output token.

- `routesB`:          Route used to convert tokenB into output token.


## Return Values:
- amountOutMinA   Minimum output expected from swapping tokenA into output token.

- amountOutMinB   Minimum output expected from swapping tokenB into output token.

- amountAMin      Minimum amount of tokenA expected from withdrawing liquidity.

- amountBMin      Minimum amount of tokenB expected from withdrawing liquidity.


# Function `quoteStableLiquidityRatio(address tokenA, address tokenB, address factory) → uint256 ratio` {#IVelodromeV2Router-quoteStableLiquidityRatio-address-address-address-}
Used by zapper to determine appropriate ratio of A to B to deposit liquidity. Assumes stable pool.


## Parameters:
- `tokenA`:   tokenA of stable pool you are zapping into.

- `tokenB`:   tokenB of stable pool you are zapping into.

- `factory`:  Factory that created stable pool.


## Return Values:
- ratio   Ratio of token0 to token1 required to deposit into zap.


