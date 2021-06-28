

# Functions:
- [`constructor(contract IAddressResolver _addressResolver)`](#SynthetixGuard-constructor-contract-IAddressResolver-)
- [`txGuard(address _poolManagerLogic, address, bytes data)`](#SynthetixGuard-txGuard-address-address-bytes-)
- [`getAssetProxy(bytes32 key)`](#SynthetixGuard-getAssetProxy-bytes32-)


# Function `constructor(contract IAddressResolver _addressResolver)` {#SynthetixGuard-constructor-contract-IAddressResolver-}
No description
# Function `txGuard(address _poolManagerLogic, address, bytes data) → uint8 txType` {#SynthetixGuard-txGuard-address-address-bytes-}
It supports exchangeWithTracking functionality

## Parameters:
- `_poolManagerLogic`: the pool manager logic

- `data`: the transaction data

## Return Values:
- txType the transaction type of a given transaction data. 2 for `Exchange` type
# Function `getAssetProxy(bytes32 key) → address` {#SynthetixGuard-getAssetProxy-bytes32-}
No description

