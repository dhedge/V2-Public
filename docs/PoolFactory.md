A Factory to spawn pools

# Functions:
- [`initialize(address _poolLogic, address _managerLogic, address assetHandler, address daoAddress)`](#PoolFactory-initialize-address-address-address-address-)
- [`createFund(bool _privatePool, address _manager, string _managerName, string _fundName, string _fundSymbol, uint256 _managerFeeNumerator, struct IHasSupportedAsset.Asset[] _supportedAssets)`](#PoolFactory-createFund-bool-address-string-string-string-uint256-struct-IHasSupportedAsset-Asset---)
- [`getDaoAddress()`](#PoolFactory-getDaoAddress--)
- [`setDaoAddress(address daoAddress)`](#PoolFactory-setDaoAddress-address-)
- [`setDaoFee(uint256 numerator, uint256 denominator)`](#PoolFactory-setDaoFee-uint256-uint256-)
- [`getDaoFee()`](#PoolFactory-getDaoFee--)
- [`getPoolManagerFee(address pool)`](#PoolFactory-getPoolManagerFee-address-)
- [`setPoolManagerFeeNumerator(address pool, uint256 numerator)`](#PoolFactory-setPoolManagerFeeNumerator-address-uint256-)
- [`getMaximumManagerFee()`](#PoolFactory-getMaximumManagerFee--)
- [`setMaximumManagerFeeNumeratorChange(uint256 amount)`](#PoolFactory-setMaximumManagerFeeNumeratorChange-uint256-)
- [`getMaximumManagerFeeNumeratorChange()`](#PoolFactory-getMaximumManagerFeeNumeratorChange--)
- [`setManagerFeeNumeratorChangeDelay(uint256 delay)`](#PoolFactory-setManagerFeeNumeratorChangeDelay-uint256-)
- [`getManagerFeeNumeratorChangeDelay()`](#PoolFactory-getManagerFeeNumeratorChangeDelay--)
- [`setExitCooldown(uint256 cooldown)`](#PoolFactory-setExitCooldown-uint256-)
- [`getExitCooldown()`](#PoolFactory-getExitCooldown--)
- [`setMaximumSupportedAssetCount(uint256 count)`](#PoolFactory-setMaximumSupportedAssetCount-uint256-)
- [`getMaximumSupportedAssetCount()`](#PoolFactory-getMaximumSupportedAssetCount--)
- [`isValidAsset(address asset)`](#PoolFactory-isValidAsset-address-)
- [`getAssetPrice(address asset)`](#PoolFactory-getAssetPrice-address-)
- [`getAssetType(address asset)`](#PoolFactory-getAssetType-address-)
- [`getAssetHandler()`](#PoolFactory-getAssetHandler--)
- [`setAssetHandler(address assetHandler)`](#PoolFactory-setAssetHandler-address-)
- [`setTrackingCode(bytes32 code)`](#PoolFactory-setTrackingCode-bytes32-)
- [`getTrackingCode()`](#PoolFactory-getTrackingCode--)
- [`upgradePoolBatch(uint256 startIndex, uint256 endIndex, uint256 sourceVersion, uint256 targetVersion, bytes data)`](#PoolFactory-upgradePoolBatch-uint256-uint256-uint256-uint256-bytes-)
- [`getGuard(address extContract)`](#PoolFactory-getGuard-address-)
- [`setContractGuard(address extContract, address guardAddress)`](#PoolFactory-setContractGuard-address-address-)
- [`setAssetGuard(uint8 assetType, address guardAddress)`](#PoolFactory-setAssetGuard-uint8-address-)
- [`pause()`](#PoolFactory-pause--)
- [`unpause()`](#PoolFactory-unpause--)
- [`isPaused()`](#PoolFactory-isPaused--)
- [`getDeployedFunds()`](#PoolFactory-getDeployedFunds--)

# Events:
- [`FundCreated(address fundAddress, bool isPoolPrivate, string fundName, string managerName, address manager, uint256 time, uint256 managerFeeNumerator, uint256 managerFeeDenominator)`](#PoolFactory-FundCreated-address-bool-string-string-address-uint256-uint256-uint256-)
- [`DaoAddressSet(address dao)`](#PoolFactory-DaoAddressSet-address-)
- [`DaoFeeSet(uint256 numerator, uint256 denominator)`](#PoolFactory-DaoFeeSet-uint256-uint256-)
- [`ExitFeeSet(uint256 numerator, uint256 denominator)`](#PoolFactory-ExitFeeSet-uint256-uint256-)
- [`ExitCooldownSet(uint256 cooldown)`](#PoolFactory-ExitCooldownSet-uint256-)
- [`MaximumSupportedAssetCountSet(uint256 count)`](#PoolFactory-MaximumSupportedAssetCountSet-uint256-)
- [`LogUpgrade(address manager, address pool)`](#PoolFactory-LogUpgrade-address-address-)

# Function `initialize(address _poolLogic, address _managerLogic, address assetHandler, address daoAddress)` {#PoolFactory-initialize-address-address-address-address-}
No description
# Function `createFund(bool _privatePool, address _manager, string _managerName, string _fundName, string _fundSymbol, uint256 _managerFeeNumerator, struct IHasSupportedAsset.Asset[] _supportedAssets) → address` {#PoolFactory-createFund-bool-address-string-string-string-uint256-struct-IHasSupportedAsset-Asset---}
No description
# Function `getDaoAddress() → address` {#PoolFactory-getDaoAddress--}
No description
# Function `setDaoAddress(address daoAddress)` {#PoolFactory-setDaoAddress-address-}
No description
# Function `setDaoFee(uint256 numerator, uint256 denominator)` {#PoolFactory-setDaoFee-uint256-uint256-}
No description
# Function `getDaoFee() → uint256, uint256` {#PoolFactory-getDaoFee--}
No description
# Function `getPoolManagerFee(address pool) → uint256, uint256` {#PoolFactory-getPoolManagerFee-address-}
No description
# Function `setPoolManagerFeeNumerator(address pool, uint256 numerator)` {#PoolFactory-setPoolManagerFeeNumerator-address-uint256-}
No description
# Function `getMaximumManagerFee() → uint256, uint256` {#PoolFactory-getMaximumManagerFee--}
No description
# Function `setMaximumManagerFeeNumeratorChange(uint256 amount)` {#PoolFactory-setMaximumManagerFeeNumeratorChange-uint256-}
No description
# Function `getMaximumManagerFeeNumeratorChange() → uint256` {#PoolFactory-getMaximumManagerFeeNumeratorChange--}
No description
# Function `setManagerFeeNumeratorChangeDelay(uint256 delay)` {#PoolFactory-setManagerFeeNumeratorChangeDelay-uint256-}
No description
# Function `getManagerFeeNumeratorChangeDelay() → uint256` {#PoolFactory-getManagerFeeNumeratorChangeDelay--}
No description
# Function `setExitCooldown(uint256 cooldown)` {#PoolFactory-setExitCooldown-uint256-}
No description
# Function `getExitCooldown() → uint256` {#PoolFactory-getExitCooldown--}
No description
# Function `setMaximumSupportedAssetCount(uint256 count)` {#PoolFactory-setMaximumSupportedAssetCount-uint256-}
No description
# Function `getMaximumSupportedAssetCount() → uint256` {#PoolFactory-getMaximumSupportedAssetCount--}
No description
# Function `isValidAsset(address asset) → bool` {#PoolFactory-isValidAsset-address-}
No description
# Function `getAssetPrice(address asset) → uint256` {#PoolFactory-getAssetPrice-address-}
No description
# Function `getAssetType(address asset) → uint8` {#PoolFactory-getAssetType-address-}
No description
# Function `getAssetHandler() → address` {#PoolFactory-getAssetHandler--}
No description
# Function `setAssetHandler(address assetHandler)` {#PoolFactory-setAssetHandler-address-}
No description
# Function `setTrackingCode(bytes32 code)` {#PoolFactory-setTrackingCode-bytes32-}
No description
# Function `getTrackingCode() → bytes32` {#PoolFactory-getTrackingCode--}
No description
# Function `upgradePoolBatch(uint256 startIndex, uint256 endIndex, uint256 sourceVersion, uint256 targetVersion, bytes data)` {#PoolFactory-upgradePoolBatch-uint256-uint256-uint256-uint256-bytes-}
No description
# Function `getGuard(address extContract) → address` {#PoolFactory-getGuard-address-}
No description
# Function `setContractGuard(address extContract, address guardAddress)` {#PoolFactory-setContractGuard-address-address-}
No description
# Function `setAssetGuard(uint8 assetType, address guardAddress)` {#PoolFactory-setAssetGuard-uint8-address-}
No description
# Function `pause()` {#PoolFactory-pause--}
No description
# Function `unpause()` {#PoolFactory-unpause--}
No description
# Function `isPaused() → bool` {#PoolFactory-isPaused--}
No description
# Function `getDeployedFunds() → address[]` {#PoolFactory-getDeployedFunds--}
No description
## Return Values:
- full array of deployed funds

# Event `FundCreated(address fundAddress, bool isPoolPrivate, string fundName, string managerName, address manager, uint256 time, uint256 managerFeeNumerator, uint256 managerFeeDenominator)` {#PoolFactory-FundCreated-address-bool-string-string-address-uint256-uint256-uint256-}
No description
# Event `DaoAddressSet(address dao)` {#PoolFactory-DaoAddressSet-address-}
No description
# Event `DaoFeeSet(uint256 numerator, uint256 denominator)` {#PoolFactory-DaoFeeSet-uint256-uint256-}
No description
# Event `ExitFeeSet(uint256 numerator, uint256 denominator)` {#PoolFactory-ExitFeeSet-uint256-uint256-}
No description
# Event `ExitCooldownSet(uint256 cooldown)` {#PoolFactory-ExitCooldownSet-uint256-}
No description
# Event `MaximumSupportedAssetCountSet(uint256 count)` {#PoolFactory-MaximumSupportedAssetCountSet-uint256-}
No description
# Event `LogUpgrade(address manager, address pool)` {#PoolFactory-LogUpgrade-address-address-}
No description
