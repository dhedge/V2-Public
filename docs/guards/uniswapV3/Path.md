## `Path`






### `hasMultiplePools(bytes path) → bool` (internal)

Returns true iff the path contains two or more pools




### `decodeFirstPool(bytes path) → address tokenA, address tokenB, uint24 fee` (internal)

Decodes the first pool in path




### `getFirstPool(bytes path) → bytes` (internal)

Gets the segment corresponding to the first pool in the path




### `skipToken(bytes path) → bytes` (internal)

Skips a token + fee element from the buffer and returns the remainder




### `getPoolAddress(bytes path) → address` (internal)

Gets address from the pool





