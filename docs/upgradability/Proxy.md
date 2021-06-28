Implements delegation of calls to other contracts, with proper
forwarding of return values and bubbling of failures.
It defines a fallback function that delegates all calls to the address
returned by the abstract _implementation() internal function.

# Functions:
- [`fallback()`](#Proxy-fallback--)
- [`receive()`](#Proxy-receive--)


# Function `fallback()` {#Proxy-fallback--}
Fallback function.
Implemented entirely in `_fallback`.
# Function `receive()` {#Proxy-receive--}
No description

