

# Functions:
- [`constructor(uint256 _uniV3PositionsLimit)`](#UniswapV3NonfungiblePositionGuard-constructor-uint256-)
- [`txGuard(address _poolManagerLogic, address to, bytes data)`](#UniswapV3NonfungiblePositionGuard-txGuard-address-address-bytes-)

# Events:
- [`Mint(address fundAddress, address token0, address token1, uint24 fee, int24 tickLower, int24 tickUpper, uint256 amount0Desired, uint256 amount1Desired, uint256 amount0Min, uint256 amount1Min, uint256 time)`](#UniswapV3NonfungiblePositionGuard-Mint-address-address-address-uint24-int24-int24-uint256-uint256-uint256-uint256-uint256-)
- [`IncreaseLiquidity(address fundAddress, uint256 tokenId, uint256 amount0Desired, uint256 amount1Desired, uint256 amount0Min, uint256 amount1Min, uint256 time)`](#UniswapV3NonfungiblePositionGuard-IncreaseLiquidity-address-uint256-uint256-uint256-uint256-uint256-uint256-)
- [`DecreaseLiquidity(address fundAddress, uint256 tokenId, uint128 liquidity, uint256 amount0Min, uint256 amount1Min, uint256 time)`](#UniswapV3NonfungiblePositionGuard-DecreaseLiquidity-address-uint256-uint128-uint256-uint256-uint256-)
- [`Burn(address fundAddress, uint256 tokenId, uint256 time)`](#UniswapV3NonfungiblePositionGuard-Burn-address-uint256-uint256-)
- [`Collect(address fundAddress, uint256 tokenId, uint128 amount0Max, uint128 amount1Max, uint256 time)`](#UniswapV3NonfungiblePositionGuard-Collect-address-uint256-uint128-uint128-uint256-)


# Function `constructor(uint256 _uniV3PositionsLimit)` {#UniswapV3NonfungiblePositionGuard-constructor-uint256-}
No description




# Function `txGuard(address _poolManagerLogic, address to, bytes data) → uint16 txType, bool` {#UniswapV3NonfungiblePositionGuard-txGuard-address-address-bytes-}
Transaction guard for Uniswap V3 non-fungible Position Manager


## Parameters:
- `_poolManagerLogic`: Pool address

- `data`: Transaction call data attempt by manager


## Return Values:
- txType transaction type described in PoolLogic

- isPublic if the transaction is public or private


