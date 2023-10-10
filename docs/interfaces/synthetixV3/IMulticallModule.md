

# Functions:
- [`multicall(bytes[] data)`](#IMulticallModule-multicall-bytes---)



# Function `multicall(bytes[] data) → bytes[] results` {#IMulticallModule-multicall-bytes---}
Executes multiple transaction payloads in a single transaction.


## Parameters:
- `data`: Array of calldata objects, one for each function that is to be called in the system.


## Return Values:
- results Array of each `delegatecall`'s response corresponding to the incoming calldata array.


