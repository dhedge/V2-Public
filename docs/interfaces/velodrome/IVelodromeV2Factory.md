

# Functions:
- [`allPoolsLength()`](#IVelodromeV2Factory-allPoolsLength--)
- [`isPool(address pool)`](#IVelodromeV2Factory-isPool-address-)
- [`isPair(address pool)`](#IVelodromeV2Factory-isPair-address-)
- [`getPool(address tokenA, address tokenB, bool stable)`](#IVelodromeV2Factory-getPool-address-address-bool-)
- [`getPool(address tokenA, address tokenB, uint24 fee)`](#IVelodromeV2Factory-getPool-address-address-uint24-)
- [`getPair(address tokenA, address tokenB, bool stable)`](#IVelodromeV2Factory-getPair-address-address-bool-)
- [`setVoter(address _voter)`](#IVelodromeV2Factory-setVoter-address-)
- [`setSinkConverter(address _sinkConvert, address _velo, address _veloV2)`](#IVelodromeV2Factory-setSinkConverter-address-address-address-)
- [`setPauser(address _pauser)`](#IVelodromeV2Factory-setPauser-address-)
- [`setPauseState(bool _state)`](#IVelodromeV2Factory-setPauseState-bool-)
- [`setFeeManager(address _feeManager)`](#IVelodromeV2Factory-setFeeManager-address-)
- [`setFee(bool _stable, uint256 _fee)`](#IVelodromeV2Factory-setFee-bool-uint256-)
- [`setCustomFee(address _pool, uint256 _fee)`](#IVelodromeV2Factory-setCustomFee-address-uint256-)
- [`getFee(address _pool, bool _stable)`](#IVelodromeV2Factory-getFee-address-bool-)
- [`createPool(address tokenA, address tokenB, bool stable)`](#IVelodromeV2Factory-createPool-address-address-bool-)
- [`createPool(address tokenA, address tokenB, uint24 fee)`](#IVelodromeV2Factory-createPool-address-address-uint24-)
- [`createPair(address tokenA, address tokenB, bool stable)`](#IVelodromeV2Factory-createPair-address-address-bool-)
- [`isPaused()`](#IVelodromeV2Factory-isPaused--)
- [`velo()`](#IVelodromeV2Factory-velo--)
- [`veloV2()`](#IVelodromeV2Factory-veloV2--)
- [`voter()`](#IVelodromeV2Factory-voter--)
- [`sinkConverter()`](#IVelodromeV2Factory-sinkConverter--)
- [`implementation()`](#IVelodromeV2Factory-implementation--)



# Function `allPoolsLength() → uint256` {#IVelodromeV2Factory-allPoolsLength--}
returns the number of pools created from this factory




# Function `isPool(address pool) → bool` {#IVelodromeV2Factory-isPool-address-}
Is a valid pool created by this factory.





# Function `isPair(address pool) → bool` {#IVelodromeV2Factory-isPair-address-}
Support for Velodrome v1 which wraps around isPool(pool);





# Function `getPool(address tokenA, address tokenB, bool stable) → address` {#IVelodromeV2Factory-getPool-address-address-bool-}
Return address of pool created by this factory


## Parameters:
- `tokenA`: .

- `tokenB`: .

- `stable`: True if stable, false if volatile



# Function `getPool(address tokenA, address tokenB, uint24 fee) → address` {#IVelodromeV2Factory-getPool-address-address-uint24-}
Support for v3-style pools which wraps around getPool(tokenA,tokenB,stable)


## Parameters:
- `tokenA`: .

- `tokenB`: .

- `fee`:  1 if stable, 0 if volatile, else returns address(0)



# Function `getPair(address tokenA, address tokenB, bool stable) → address` {#IVelodromeV2Factory-getPair-address-address-bool-}
Support for Velodrome v1 pools as a "pool" was previously referenced as "pair"
Wraps around getPool(tokenA,tokenB,stable)




# Function `setVoter(address _voter)` {#IVelodromeV2Factory-setVoter-address-}
No description

## Parameters:
- `_voter`: .



# Function `setSinkConverter(address _sinkConvert, address _velo, address _veloV2)` {#IVelodromeV2Factory-setSinkConverter-address-address-address-}
No description




# Function `setPauser(address _pauser)` {#IVelodromeV2Factory-setPauser-address-}
No description




# Function `setPauseState(bool _state)` {#IVelodromeV2Factory-setPauseState-bool-}
No description




# Function `setFeeManager(address _feeManager)` {#IVelodromeV2Factory-setFeeManager-address-}
No description




# Function `setFee(bool _stable, uint256 _fee)` {#IVelodromeV2Factory-setFee-bool-uint256-}
Set default fee for stable and volatile pools.


## Parameters:
- `_stable`: Stable or volatile pool.

- `_fee`: .



# Function `setCustomFee(address _pool, uint256 _fee)` {#IVelodromeV2Factory-setCustomFee-address-uint256-}
Set overriding fee for a pool from the default





# Function `getFee(address _pool, bool _stable) → uint256` {#IVelodromeV2Factory-getFee-address-bool-}
Returns fee for a pool, as custom fees are possible.




# Function `createPool(address tokenA, address tokenB, bool stable) → address pool` {#IVelodromeV2Factory-createPool-address-address-bool-}
Create a pool given two tokens and if they're stable/volatile


## Parameters:
- `tokenA`: .

- `tokenB`: .

- `stable`: .



# Function `createPool(address tokenA, address tokenB, uint24 fee) → address pool` {#IVelodromeV2Factory-createPool-address-address-uint24-}
Support for v3-style pools which wraps around createPool(tokena,tokenB,stable)


## Parameters:
- `tokenA`: .

- `tokenB`: .

- `fee`: 1 if stable, 0 if volatile, else revert



# Function `createPair(address tokenA, address tokenB, bool stable) → address pool` {#IVelodromeV2Factory-createPair-address-address-bool-}
Support for Velodrome v1 which wraps around createPool(tokenA,tokenB,stable)




# Function `isPaused() → bool` {#IVelodromeV2Factory-isPaused--}
No description




# Function `velo() → address` {#IVelodromeV2Factory-velo--}
No description




# Function `veloV2() → address` {#IVelodromeV2Factory-veloV2--}
No description




# Function `voter() → address` {#IVelodromeV2Factory-voter--}
No description




# Function `sinkConverter() → address` {#IVelodromeV2Factory-sinkConverter--}
No description




# Function `implementation() → address` {#IVelodromeV2Factory-implementation--}
No description




