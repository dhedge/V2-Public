## `PoolFactory`



A Factory to spawn pools

### `onlyDao()`





### `onlyPool()`





### `onlyPoolManager()`






### `initialize(address _poolLogic, address _managerLogic, address assetHandler, address daoAddress)` (public)





### `createFund(bool _privatePool, address _manager, string _managerName, string _fundName, string _fundSymbol, uint256 _managerFeeNumerator, struct IHasSupportedAsset.Asset[] _supportedAssets) → address` (public)





### `getDaoAddress() → address` (public)





### `setDaoAddress(address daoAddress)` (public)





### `_setDaoAddress(address daoAddress)` (internal)





### `setDaoFee(uint256 numerator, uint256 denominator)` (public)





### `_setDaoFee(uint256 numerator, uint256 denominator)` (internal)





### `getDaoFee() → uint256, uint256` (public)





### `getPoolManagerFee(address pool) → uint256, uint256` (external)





### `setPoolManagerFeeNumerator(address pool, uint256 numerator)` (external)





### `_setPoolManagerFee(address pool, uint256 numerator, uint256 denominator)` (internal)





### `getMaximumManagerFee() → uint256, uint256` (public)





### `_setMaximumManagerFee(uint256 numerator, uint256 denominator)` (internal)





### `setMaximumManagerFeeNumeratorChange(uint256 amount)` (public)





### `getMaximumManagerFeeNumeratorChange() → uint256` (public)





### `setManagerFeeNumeratorChangeDelay(uint256 delay)` (public)





### `getManagerFeeNumeratorChangeDelay() → uint256` (public)





### `setExitCooldown(uint256 cooldown)` (external)





### `_setExitCooldown(uint256 cooldown)` (internal)





### `getExitCooldown() → uint256` (external)





### `setMaximumSupportedAssetCount(uint256 count)` (external)





### `_setMaximumSupportedAssetCount(uint256 count)` (internal)





### `getMaximumSupportedAssetCount() → uint256` (external)





### `isValidAsset(address asset) → bool` (public)





### `getAssetPrice(address asset) → uint256` (external)

Returns the latest price of a given asset



### `getAssetType(address asset) → uint8` (external)





### `getAssetHandler() → address` (public)





### `setAssetHandler(address assetHandler)` (public)





### `_setAssetHandler(address assetHandler)` (internal)





### `setTrackingCode(bytes32 code)` (external)





### `_setTrackingCode(bytes32 code)` (internal)





### `getTrackingCode() → bytes32` (public)





### `_upgradePool(address pool, bytes data, uint256 targetVersion)` (internal)



Backdoor function


### `upgradePoolBatch(uint256 startIndex, uint256 endIndex, uint256 sourceVersion, uint256 targetVersion, bytes data)` (external)





### `getGuard(address extContract) → address` (public)





### `setContractGuard(address extContract, address guardAddress)` (public)





### `_setContractGuard(address extContract, address guardAddress)` (internal)





### `setAssetGuard(uint8 assetType, address guardAddress)` (public)





### `_setAssetGuard(uint8 assetType, address guardAddress)` (internal)





### `pause()` (public)





### `unpause()` (public)





### `isPaused() → bool` (public)





### `getDeployedFunds() → address[]` (public)

Return full array of deployed funds





### `FundCreated(address fundAddress, bool isPoolPrivate, string fundName, string managerName, address manager, uint256 time, uint256 managerFeeNumerator, uint256 managerFeeDenominator)`





### `DaoAddressSet(address dao)`





### `DaoFeeSet(uint256 numerator, uint256 denominator)`





### `ExitFeeSet(uint256 numerator, uint256 denominator)`





### `ExitCooldownSet(uint256 cooldown)`





### `MaximumSupportedAssetCountSet(uint256 count)`





### `LogUpgrade(address manager, address pool)`





