Enables calling multiple methods in a single call to the contract with optional validation

# Functions:
- [`multicall(uint256 deadline, bytes[] data)`](#IMulticallExtended-multicall-uint256-bytes---)
- [`multicall(bytes32 previousBlockhash, bytes[] data)`](#IMulticallExtended-multicall-bytes32-bytes---)



# Function `multicall(uint256 deadline, bytes[] data) → bytes[] results` {#IMulticallExtended-multicall-uint256-bytes---}
Call multiple functions in the current contract and return the data from all of them if they all succeed


## Parameters:
- `deadline`: The time by which this function must be called before failing

- `data`: The encoded function data for each of the calls to make to this contract


## Return Values:
- results The results from each of the calls passed in via data


# Function `multicall(bytes32 previousBlockhash, bytes[] data) → bytes[] results` {#IMulticallExtended-multicall-bytes32-bytes---}
Call multiple functions in the current contract and return the data from all of them if they all succeed


## Parameters:
- `previousBlockhash`: The expected parent blockHash

- `data`: The encoded function data for each of the calls to make to this contract


## Return Values:
- results The results from each of the calls passed in via data


