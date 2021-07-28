

# Functions:
- [`initialize(address _poolLogic, address _managerLogic, address assetHandler, address _daoAddress, address _governanceAddress)`](#PoolFactoryV23-initialize-address-address-address-address-address-)
- [`createFund(bool _privatePool, address _manager, string _managerName, string _fundName, string _fundSymbol, uint256 _managerFeeNumerator, struct IHasSupportedAssetV23.Asset[] _supportedAssets)`](#PoolFactoryV23-createFund-bool-address-string-string-string-uint256-struct-IHasSupportedAssetV23-Asset---)
- [`setDAOAddress(address _daoAddress)`](#PoolFactoryV23-setDAOAddress-address-)
- [`setGovernanceAddress(address _governanceAddress)`](#PoolFactoryV23-setGovernanceAddress-address-)
- [`setDaoFee(uint256 numerator, uint256 denominator)`](#PoolFactoryV23-setDaoFee-uint256-uint256-)
- [`getDaoFee()`](#PoolFactoryV23-getDaoFee--)
- [`getPoolManagerFee(address pool)`](#PoolFactoryV23-getPoolManagerFee-address-)
- [`setPoolManagerFeeNumerator(address pool, uint256 numerator)`](#PoolFactoryV23-setPoolManagerFeeNumerator-address-uint256-)
- [`getMaximumManagerFee()`](#PoolFactoryV23-getMaximumManagerFee--)
- [`setMaximumManagerFeeNumeratorChange(uint256 amount)`](#PoolFactoryV23-setMaximumManagerFeeNumeratorChange-uint256-)
- [`getMaximumManagerFeeNumeratorChange()`](#PoolFactoryV23-getMaximumManagerFeeNumeratorChange--)
- [`setManagerFeeNumeratorChangeDelay(uint256 delay)`](#PoolFactoryV23-setManagerFeeNumeratorChangeDelay-uint256-)
- [`getManagerFeeNumeratorChangeDelay()`](#PoolFactoryV23-getManagerFeeNumeratorChangeDelay--)
- [`setExitCooldown(uint256 cooldown)`](#PoolFactoryV23-setExitCooldown-uint256-)
- [`getExitCooldown()`](#PoolFactoryV23-getExitCooldown--)
- [`setMaximumSupportedAssetCount(uint256 count)`](#PoolFactoryV23-setMaximumSupportedAssetCount-uint256-)
- [`getMaximumSupportedAssetCount()`](#PoolFactoryV23-getMaximumSupportedAssetCount--)
- [`isValidAsset(address asset)`](#PoolFactoryV23-isValidAsset-address-)
- [`getAssetPrice(address asset)`](#PoolFactoryV23-getAssetPrice-address-)
- [`getAssetType(address asset)`](#PoolFactoryV23-getAssetType-address-)
- [`getAssetHandler()`](#PoolFactoryV23-getAssetHandler--)
- [`setAssetHandler(address assetHandler)`](#PoolFactoryV23-setAssetHandler-address-)
- [`upgradePoolBatch(uint256 startIndex, uint256 endIndex, uint256 sourceVersion, uint256 targetVersion, bytes data)`](#PoolFactoryV23-upgradePoolBatch-uint256-uint256-uint256-uint256-bytes-)
- [`pause()`](#PoolFactoryV23-pause--)
- [`unpause()`](#PoolFactoryV23-unpause--)
- [`isPaused()`](#PoolFactoryV23-isPaused--)
- [`getGuard(address extContract)`](#PoolFactoryV23-getGuard-address-)
- [`getAssetGuard(address extContract)`](#PoolFactoryV23-getAssetGuard-address-)
- [`getDeployedFunds()`](#PoolFactoryV23-getDeployedFunds--)

# Events:
- [`FundCreated(address fundAddress, bool isPoolPrivate, string fundName, string managerName, address manager, uint256 time, uint256 managerFeeNumerator, uint256 managerFeeDenominator)`](#PoolFactoryV23-FundCreated-address-bool-string-string-address-uint256-uint256-uint256-)
- [`DAOAddressSet(address daoAddress)`](#PoolFactoryV23-DAOAddressSet-address-)
- [`GovernanceAddressSet(address governanceAddress)`](#PoolFactoryV23-GovernanceAddressSet-address-)
- [`DaoFeeSet(uint256 numerator, uint256 denominator)`](#PoolFactoryV23-DaoFeeSet-uint256-uint256-)
- [`ExitFeeSet(uint256 numerator, uint256 denominator)`](#PoolFactoryV23-ExitFeeSet-uint256-uint256-)
- [`ExitCooldownSet(uint256 cooldown)`](#PoolFactoryV23-ExitCooldownSet-uint256-)
- [`MaximumSupportedAssetCountSet(uint256 count)`](#PoolFactoryV23-MaximumSupportedAssetCountSet-uint256-)
- [`LogUpgrade(address manager, address pool)`](#PoolFactoryV23-LogUpgrade-address-address-)
- [`SetPoolManagerFee(uint256 numerator, uint256 denominator)`](#PoolFactoryV23-SetPoolManagerFee-uint256-uint256-)
- [`SetMaximumManagerFee(uint256 numerator, uint256 denominator)`](#PoolFactoryV23-SetMaximumManagerFee-uint256-uint256-)
- [`SetMaximumManagerFeeNumeratorChange(uint256 amount)`](#PoolFactoryV23-SetMaximumManagerFeeNumeratorChange-uint256-)
- [`SetAssetHandler(address assetHandler)`](#PoolFactoryV23-SetAssetHandler-address-)
- [`SetTrackingCode(bytes32 code)`](#PoolFactoryV23-SetTrackingCode-bytes32-)


# Function `initialize(address _poolLogic, address _managerLogic, address assetHandler, address _daoAddress, address _governanceAddress)` {#PoolFactoryV23-initialize-address-address-address-address-address-}
No description




# Function `createFund(bool _privatePool, address _manager, string _managerName, string _fundName, string _fundSymbol, uint256 _managerFeeNumerator, struct IHasSupportedAssetV23.Asset[] _supportedAssets) → address` {#PoolFactoryV23-createFund-bool-address-string-string-string-uint256-struct-IHasSupportedAssetV23-Asset---}
No description




# Function `setDAOAddress(address _daoAddress)` {#PoolFactoryV23-setDAOAddress-address-}
No description






# Function `setGovernanceAddress(address _governanceAddress)` {#PoolFactoryV23-setGovernanceAddress-address-}
No description






# Function `setDaoFee(uint256 numerator, uint256 denominator)` {#PoolFactoryV23-setDaoFee-uint256-uint256-}
No description






# Function `getDaoFee() → uint256, uint256` {#PoolFactoryV23-getDaoFee--}
No description




# Function `getPoolManagerFee(address pool) → uint256, uint256` {#PoolFactoryV23-getPoolManagerFee-address-}
No description




# Function `setPoolManagerFeeNumerator(address pool, uint256 numerator)` {#PoolFactoryV23-setPoolManagerFeeNumerator-address-uint256-}
No description






# Function `getMaximumManagerFee() → uint256, uint256` {#PoolFactoryV23-getMaximumManagerFee--}
No description






# Function `setMaximumManagerFeeNumeratorChange(uint256 amount)` {#PoolFactoryV23-setMaximumManagerFeeNumeratorChange-uint256-}
No description




# Function `getMaximumManagerFeeNumeratorChange() → uint256` {#PoolFactoryV23-getMaximumManagerFeeNumeratorChange--}
No description




# Function `setManagerFeeNumeratorChangeDelay(uint256 delay)` {#PoolFactoryV23-setManagerFeeNumeratorChangeDelay-uint256-}
No description




# Function `getManagerFeeNumeratorChangeDelay() → uint256` {#PoolFactoryV23-getManagerFeeNumeratorChangeDelay--}
No description




# Function `setExitCooldown(uint256 cooldown)` {#PoolFactoryV23-setExitCooldown-uint256-}
No description






# Function `getExitCooldown() → uint256` {#PoolFactoryV23-getExitCooldown--}
No description




# Function `setMaximumSupportedAssetCount(uint256 count)` {#PoolFactoryV23-setMaximumSupportedAssetCount-uint256-}
No description






# Function `getMaximumSupportedAssetCount() → uint256` {#PoolFactoryV23-getMaximumSupportedAssetCount--}
No description




# Function `isValidAsset(address asset) → bool` {#PoolFactoryV23-isValidAsset-address-}
No description




# Function `getAssetPrice(address asset) → uint256` {#PoolFactoryV23-getAssetPrice-address-}
Returns the latest price of a given asset




# Function `getAssetType(address asset) → uint16` {#PoolFactoryV23-getAssetType-address-}
No description




# Function `getAssetHandler() → address` {#PoolFactoryV23-getAssetHandler--}
No description




# Function `setAssetHandler(address assetHandler)` {#PoolFactoryV23-setAssetHandler-address-}
No description








# Function `upgradePoolBatch(uint256 startIndex, uint256 endIndex, uint256 sourceVersion, uint256 targetVersion, bytes data)` {#PoolFactoryV23-upgradePoolBatch-uint256-uint256-uint256-uint256-bytes-}
No description




# Function `pause()` {#PoolFactoryV23-pause--}
No description




# Function `unpause()` {#PoolFactoryV23-unpause--}
No description




# Function `isPaused() → bool` {#PoolFactoryV23-isPaused--}
No description




# Function `getGuard(address extContract) → address guard` {#PoolFactoryV23-getGuard-address-}
No description




# Function `getAssetGuard(address extContract) → address guard` {#PoolFactoryV23-getAssetGuard-address-}
No description




# Function `getDeployedFunds() → address[]` {#PoolFactoryV23-getDeployedFunds--}
Return full array of deployed funds



## Return Values:
- full array of deployed funds


