

# Functions:
- [`constructor(contract IAddressResolver _addressResolver)`](#SynthetixGuard-constructor-contract-IAddressResolver-)
- [`txGuard(address _poolManagerLogic, address, bytes data)`](#SynthetixGuard-txGuard-address-address-bytes-)
- [`getAssetProxy(bytes32 key)`](#SynthetixGuard-getAssetProxy-bytes32-)



# Function `constructor(contract IAddressResolver _addressResolver)` {#SynthetixGuard-constructor-contract-IAddressResolver-}
No description




# Function `txGuard(address _poolManagerLogic, address, bytes data) → uint16 txType, bool` {#SynthetixGuard-txGuard-address-address-bytes-}
Transaction guard for Synthetix Exchanger


## Parameters:
- `_poolManagerLogic`: the pool manager logic

- `data`: the transaction data


## Return Values:
- txType the transaction type of a given transaction data. 2 for `Exchange` type

- isPublic if the transaction is public or private


# Function `getAssetProxy(bytes32 key) → address proxy` {#SynthetixGuard-getAssetProxy-bytes32-}
Get asset proxy address from addressResolver


## Parameters:
- `key`: the key of the asset


## Return Values:
- proxy the proxy address of the asset


