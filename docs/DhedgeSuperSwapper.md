

# Functions:
- [`constructor(contract IUniswapV2Router[] _uniV2Routers, contract ICurveCryptoSwap[] _curvePools)`](#DhedgeSuperSwapper-constructor-contract-IUniswapV2Router---contract-ICurveCryptoSwap---)
- [`swapExactTokensForTokens(uint256 amountIn, uint256 amountOutMin, address[] path, address to, uint256 deadline)`](#DhedgeSuperSwapper-swapExactTokensForTokens-uint256-uint256-address---address-uint256-)
- [`swapTokensForExactTokens(uint256 expectedAmountOut, uint256 amountInMax, address[] path, address to, uint256 deadline)`](#DhedgeSuperSwapper-swapTokensForExactTokens-uint256-uint256-address---address-uint256-)
- [`getAmountsOut(uint256 amountIn, address[] path)`](#DhedgeSuperSwapper-getAmountsOut-uint256-address---)
- [`getBestAmountOutUniV2Router(uint256 amountIn, address[] path)`](#DhedgeSuperSwapper-getBestAmountOutUniV2Router-uint256-address---)
- [`getAmountOutUniV2(contract IUniswapV2Router uniV2Router, uint256 amountIn, address[] path)`](#DhedgeSuperSwapper-getAmountOutUniV2-contract-IUniswapV2Router-uint256-address---)
- [`getBestAmountInUniV2Router(uint256 amountOut, address[] path)`](#DhedgeSuperSwapper-getBestAmountInUniV2Router-uint256-address---)
- [`getAmountInUniV2(contract IUniswapV2Router uniV2Router, uint256 amountOut, address[] path)`](#DhedgeSuperSwapper-getAmountInUniV2-contract-IUniswapV2Router-uint256-address---)
- [`getBestAmountOutCurvePool(uint256 amountIn, address[] path)`](#DhedgeSuperSwapper-getBestAmountOutCurvePool-uint256-address---)
- [`getAmountOutCurve(contract ICurveCryptoSwap curvePool, uint256 amountIn, address[] path)`](#DhedgeSuperSwapper-getAmountOutCurve-contract-ICurveCryptoSwap-uint256-address---)
- [`addressToString(address _addr)`](#DhedgeSuperSwapper-addressToString-address-)

# Events:
- [`Swap(address swapRouter)`](#DhedgeSuperSwapper-Swap-address-)


# Function `constructor(contract IUniswapV2Router[] _uniV2Routers, contract ICurveCryptoSwap[] _curvePools)` {#DhedgeSuperSwapper-constructor-contract-IUniswapV2Router---contract-ICurveCryptoSwap---}
No description




# Function `swapExactTokensForTokens(uint256 amountIn, uint256 amountOutMin, address[] path, address to, uint256 deadline) → uint256[] amounts` {#DhedgeSuperSwapper-swapExactTokensForTokens-uint256-uint256-address---address-uint256-}
No description




# Function `swapTokensForExactTokens(uint256 expectedAmountOut, uint256 amountInMax, address[] path, address to, uint256 deadline) → uint256[] amounts` {#DhedgeSuperSwapper-swapTokensForExactTokens-uint256-uint256-address---address-uint256-}
No description






# Function `getAmountsOut(uint256 amountIn, address[] path) → uint256[] amounts` {#DhedgeSuperSwapper-getAmountsOut-uint256-address---}
No description




# Function `getBestAmountOutUniV2Router(uint256 amountIn, address[] path) → contract IUniswapV2Router router, uint256 bestAmountOut` {#DhedgeSuperSwapper-getBestAmountOutUniV2Router-uint256-address---}
No description




# Function `getAmountOutUniV2(contract IUniswapV2Router uniV2Router, uint256 amountIn, address[] path) → uint256 amount` {#DhedgeSuperSwapper-getAmountOutUniV2-contract-IUniswapV2Router-uint256-address---}
No description




# Function `getBestAmountInUniV2Router(uint256 amountOut, address[] path) → contract IUniswapV2Router router, uint256 bestAmountIn` {#DhedgeSuperSwapper-getBestAmountInUniV2Router-uint256-address---}
No description




# Function `getAmountInUniV2(contract IUniswapV2Router uniV2Router, uint256 amountOut, address[] path) → uint256 amount` {#DhedgeSuperSwapper-getAmountInUniV2-contract-IUniswapV2Router-uint256-address---}
No description




# Function `getBestAmountOutCurvePool(uint256 amountIn, address[] path) → contract ICurveCryptoSwap pool, uint256 bestAmountOut` {#DhedgeSuperSwapper-getBestAmountOutCurvePool-uint256-address---}
No description




# Function `getAmountOutCurve(contract ICurveCryptoSwap curvePool, uint256 amountIn, address[] path) → uint256 amount` {#DhedgeSuperSwapper-getAmountOutCurve-contract-ICurveCryptoSwap-uint256-address---}
No description




# Function `addressToString(address _addr) → string` {#DhedgeSuperSwapper-addressToString-address-}
No description








