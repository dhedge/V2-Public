## `PoolManagerLogic`






### `initialize(address _factory, address _manager, string _managerName, address _poolLogic, struct IHasSupportedAsset.Asset[] _supportedAssets)` (public)





### `isSupportedAsset(address asset) → bool` (public)





### `isDepositAsset(address asset) → bool` (public)





### `validateAsset(address asset) → bool` (public)





### `changeAssets(struct IHasSupportedAsset.Asset[] _addAssets, address[] _removeAssets)` (external)





### `_changeAssets(struct IHasSupportedAsset.Asset[] _addAssets, address[] _removeAssets)` (internal)





### `_addAsset(struct IHasSupportedAsset.Asset _asset)` (internal)





### `_removeAsset(address asset)` (internal)

Remove asset from the pool


use asset address to remove from supportedAssets


### `getSupportedAssets() → struct IHasSupportedAsset.Asset[]` (public)

Get all the supported assets




### `getDepositAssets() → address[]` (public)

Get all the deposit assets




### `assetBalance(address asset) → uint256` (public)

Get asset balance including any staked balance in external contracts



### `assetValue(address asset, uint256 amount) → uint256` (public)





### `assetValue(address asset) → uint256` (public)





### `getFundComposition() → struct IHasSupportedAsset.Asset[] assets, uint256[] balances, uint256[] rates` (public)

Return the fund composition of the pool


Return assets, balances of the asset and their prices


### `getManagerFee() → uint256, uint256` (public)





### `_setManagerFeeNumerator(uint256 numerator)` (internal)





### `announceManagerFeeIncrease(uint256 numerator)` (public)





### `renounceManagerFeeIncrease()` (public)





### `commitManagerFeeIncrease()` (public)





### `setManagerFeeNumerator(uint256 numerator)` (public)





### `getManagerFeeIncreaseInfo() → uint256, uint256` (public)





### `setPoolLogic(address _poolLogic) → bool` (external)





### `totalFundValue() → uint256` (public)

Return the total fund value of the pool


Calculate the total fund value from the supported assets



### `AssetAdded(address fundAddress, address manager, address asset, bool isDeposit)`





### `AssetRemoved(address fundAddress, address manager, address asset)`





### `ManagerFeeSet(address fundAddress, address manager, uint256 numerator, uint256 denominator)`





### `ManagerFeeIncreaseAnnounced(uint256 newNumerator, uint256 announcedFeeActivationTime)`





### `ManagerFeeIncreaseRenounced()`





### `PoolLogicSet(address poolLogic, address from)`





