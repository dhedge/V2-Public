## `Proxy`



Implements delegation of calls to other contracts, with proper
forwarding of return values and bubbling of failures.
It defines a fallback function that delegates all calls to the address
returned by the abstract _implementation() internal function.


### `fallback()` (external)



Fallback function.
Implemented entirely in `_fallback`.

### `receive()` (external)





### `_implementation() → address` (internal)





### `_delegate(address implementation)` (internal)



Delegates execution to an implementation contract.
This is a low level function that doesn't return to its internal call site.
It will return to the external caller whatever the implementation returns.


### `_willFallback()` (internal)



Function that is run as the first thing in the fallback function.
Can be redefined in derived contracts to add functionality.
Redefinitions must call super._willFallback().

### `_fallback()` (internal)



fallback implementation.
Extracted to enable manual triggering.


