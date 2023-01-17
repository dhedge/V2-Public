

# Functions:
- [`constructor(address[] _assets)`](#OpenAssetGuard-constructor-address---)
- [`txGuard(address _poolManagerLogic, address to, bytes data)`](#OpenAssetGuard-txGuard-address-address-bytes-)
- [`setValidAsset(address _asset, bool _isValid)`](#OpenAssetGuard-setValidAsset-address-bool-)

# Events:
- [`SetValidAsset(address asset, bool isValid)`](#OpenAssetGuard-SetValidAsset-address-bool-)
- [`Approve(address fundAddress, address manager, address spender, uint256 amount, uint256 time)`](#OpenAssetGuard-Approve-address-address-address-uint256-uint256-)


# Function `constructor(address[] _assets)` {#OpenAssetGuard-constructor-address---}
No description




# Function `txGuard(address _poolManagerLogic, address to, bytes data) → uint16 txType, bool` {#OpenAssetGuard-txGuard-address-address-bytes-}
Transaction guard for approving assets


## Parameters:
- `_poolManagerLogic`: Pool address

- `data`: Transaction call data attempt by manager


## Return Values:
- txType transaction type described in PoolLogic

- isPublic if the transaction is public or private


# Function `setValidAsset(address _asset, bool _isValid)` {#OpenAssetGuard-setValidAsset-address-bool-}
Setting a valid asset


## Parameters:
- `_asset`: the asset address

- `_isValid`: is valid or not



