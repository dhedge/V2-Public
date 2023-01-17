

# Functions:
- [`initialize(address _poolLogic, address _managerLogic, address assetHandler, address _daoAddress, address _governanceAddress)`](#PoolFactoryV24-initialize-address-address-address-address-address-)
- [`createFund(bool _privatePool, address _manager, string _managerName, string _fundName, string _fundSymbol, uint256 _performanceFeeNumerator, struct IHasSupportedAssetV24.Asset[] _supportedAssets)`](#PoolFactoryV24-createFund-bool-address-string-string-string-uint256-struct-IHasSupportedAssetV24-Asset---)
- [`setDAOAddress(address _daoAddress)`](#PoolFactoryV24-setDAOAddress-address-)
- [`setGovernanceAddress(address _governanceAddress)`](#PoolFactoryV24-setGovernanceAddress-address-)
- [`setDaoFee(uint256 numerator, uint256 denominator)`](#PoolFactoryV24-setDaoFee-uint256-uint256-)
- [`getDaoFee()`](#PoolFactoryV24-getDaoFee--)
- [`getMaximumManagerFee()`](#PoolFactoryV24-getMaximumManagerFee--)
- [`setMaximumManagerFee(uint256 numerator)`](#PoolFactoryV24-setMaximumManagerFee-uint256-)
- [`setMaximumPerformanceFeeNumeratorChange(uint256 amount)`](#PoolFactoryV24-setMaximumPerformanceFeeNumeratorChange-uint256-)
- [`setPerformanceFeeNumeratorChangeDelay(uint256 delay)`](#PoolFactoryV24-setPerformanceFeeNumeratorChangeDelay-uint256-)
- [`setExitCooldown(uint256 cooldown)`](#PoolFactoryV24-setExitCooldown-uint256-)
- [`getExitCooldown()`](#PoolFactoryV24-getExitCooldown--)
- [`setMaximumSupportedAssetCount(uint256 count)`](#PoolFactoryV24-setMaximumSupportedAssetCount-uint256-)
- [`getMaximumSupportedAssetCount()`](#PoolFactoryV24-getMaximumSupportedAssetCount--)
- [`isValidAsset(address asset)`](#PoolFactoryV24-isValidAsset-address-)
- [`getAssetPrice(address asset)`](#PoolFactoryV24-getAssetPrice-address-)
- [`getAssetType(address asset)`](#PoolFactoryV24-getAssetType-address-)
- [`getAssetHandler()`](#PoolFactoryV24-getAssetHandler--)
- [`setAssetHandler(address assetHandler)`](#PoolFactoryV24-setAssetHandler-address-)
- [`setPoolStorageVersion(uint256 _poolStorageVersion)`](#PoolFactoryV24-setPoolStorageVersion-uint256-)
- [`upgradePoolBatch(uint256 startIndex, uint256 endIndex, uint256 sourceVersion, uint256 targetVersion, bytes data)`](#PoolFactoryV24-upgradePoolBatch-uint256-uint256-uint256-uint256-bytes-)
- [`pause()`](#PoolFactoryV24-pause--)
- [`unpause()`](#PoolFactoryV24-unpause--)
- [`isPaused()`](#PoolFactoryV24-isPaused--)
- [`getGuard(address extContract)`](#PoolFactoryV24-getGuard-address-)
- [`getAssetGuard(address extAsset)`](#PoolFactoryV24-getAssetGuard-address-)
- [`getAddress(bytes32 name)`](#PoolFactoryV24-getAddress-bytes32-)
- [`getDeployedFunds()`](#PoolFactoryV24-getDeployedFunds--)
- [`getInvestedPools(address user)`](#PoolFactoryV24-getInvestedPools-address-)
- [`getManagedPools(address manager)`](#PoolFactoryV24-getManagedPools-address-)

# Events:
- [`FundCreated(address fundAddress, bool isPoolPrivate, string fundName, string managerName, address manager, uint256 time, uint256 performanceFeeNumerator, uint256 managerFeeDenominator)`](#PoolFactoryV24-FundCreated-address-bool-string-string-address-uint256-uint256-uint256-)
- [`DAOAddressSet(address daoAddress)`](#PoolFactoryV24-DAOAddressSet-address-)
- [`GovernanceAddressSet(address governanceAddress)`](#PoolFactoryV24-GovernanceAddressSet-address-)
- [`DaoFeeSet(uint256 numerator, uint256 denominator)`](#PoolFactoryV24-DaoFeeSet-uint256-uint256-)
- [`ExitFeeSet(uint256 numerator, uint256 denominator)`](#PoolFactoryV24-ExitFeeSet-uint256-uint256-)
- [`ExitCooldownSet(uint256 cooldown)`](#PoolFactoryV24-ExitCooldownSet-uint256-)
- [`MaximumSupportedAssetCountSet(uint256 count)`](#PoolFactoryV24-MaximumSupportedAssetCountSet-uint256-)
- [`LogUpgrade(address manager, address pool)`](#PoolFactoryV24-LogUpgrade-address-address-)
- [`SetPoolManagerFee(uint256 numerator, uint256 denominator)`](#PoolFactoryV24-SetPoolManagerFee-uint256-uint256-)
- [`SetMaximumManagerFee(uint256 numerator, uint256 denominator)`](#PoolFactoryV24-SetMaximumManagerFee-uint256-uint256-)
- [`SetMaximumPerformanceFeeNumeratorChange(uint256 amount)`](#PoolFactoryV24-SetMaximumPerformanceFeeNumeratorChange-uint256-)
- [`SetAssetHandler(address assetHandler)`](#PoolFactoryV24-SetAssetHandler-address-)
- [`SetPoolStorageVersion(uint256 poolStorageVersion)`](#PoolFactoryV24-SetPoolStorageVersion-uint256-)
- [`SetPerformanceFeeNumeratorChangeDelay(uint256 delay)`](#PoolFactoryV24-SetPerformanceFeeNumeratorChangeDelay-uint256-)


# Function `initialize(address _poolLogic, address _managerLogic, address assetHandler, address _daoAddress, address _governanceAddress)` {#PoolFactoryV24-initialize-address-address-address-address-address-}
Initialize the factory


## Parameters:
- `_poolLogic`: The pool logic address

- `_managerLogic`: The manager logic address

- `assetHandler`: The address of the asset handler

- `_daoAddress`: The address of the DAO

- `_governanceAddress`: The address of the governance contract



# Function `createFund(bool _privatePool, address _manager, string _managerName, string _fundName, string _fundSymbol, uint256 _performanceFeeNumerator, struct IHasSupportedAssetV24.Asset[] _supportedAssets) → address fund` {#PoolFactoryV24-createFund-bool-address-string-string-string-uint256-struct-IHasSupportedAssetV24-Asset---}
Function to create a new fund


## Parameters:
- `_privatePool`: A boolean indicating whether the fund is private or not

- `_manager`: A manager address

- `_managerName`: The name of the manager

- `_fundName`: The name of the fund

- `_fundSymbol`: The symbol of the fund

- `_performanceFeeNumerator`: The numerator of the manager fee

- `_supportedAssets`: An array of supported assets


## Return Values:
- fund Address of the fund


# Function `setDAOAddress(address _daoAddress)` {#PoolFactoryV24-setDAOAddress-address-}
Set the DAO address


## Parameters:
- `_daoAddress`: The address of the DAO





# Function `setGovernanceAddress(address _governanceAddress)` {#PoolFactoryV24-setGovernanceAddress-address-}
Set the governance address


## Parameters:
- `_governanceAddress`: The address of the governance contract





# Function `setDaoFee(uint256 numerator, uint256 denominator)` {#PoolFactoryV24-setDaoFee-uint256-uint256-}
Set the DAO fee


## Parameters:
- `numerator`: The numerator of the DAO fee

- `denominator`: The denominator of the DAO fee





# Function `getDaoFee() → uint256, uint256` {#PoolFactoryV24-getDaoFee--}
Get the DAO fee



## Return Values:
- The numerator of the DAO fee

- The denominator of the DAO fee


# Function `getMaximumManagerFee() → uint256, uint256` {#PoolFactoryV24-getMaximumManagerFee--}
Get the maximum manager fee



## Return Values:
- The maximum manager fee numerator

- The maximum manager fee denominator


# Function `setMaximumManagerFee(uint256 numerator)` {#PoolFactoryV24-setMaximumManagerFee-uint256-}
Set the maximum manager fee


## Parameters:
- `numerator`: The numerator of the maximum manager fee





# Function `setMaximumPerformanceFeeNumeratorChange(uint256 amount)` {#PoolFactoryV24-setMaximumPerformanceFeeNumeratorChange-uint256-}
Set maximum manager fee numberator change


## Parameters:
- `amount`: The amount for the maximum manager fee numerator change



# Function `setPerformanceFeeNumeratorChangeDelay(uint256 delay)` {#PoolFactoryV24-setPerformanceFeeNumeratorChangeDelay-uint256-}
Set manager fee numberator change delay


## Parameters:
- `delay`: The delay in seconds for the manager fee numerator change



# Function `setExitCooldown(uint256 cooldown)` {#PoolFactoryV24-setExitCooldown-uint256-}
Set exit cool down time (in seconds)


## Parameters:
- `cooldown`: The cool down time in seconds





# Function `getExitCooldown() → uint256` {#PoolFactoryV24-getExitCooldown--}
Get the exit cool down time (in seconds)



## Return Values:
- The exit cool down time in seconds


# Function `setMaximumSupportedAssetCount(uint256 count)` {#PoolFactoryV24-setMaximumSupportedAssetCount-uint256-}
Set maximum supported asset count


## Parameters:
- `count`: The maximum supported asset count





# Function `getMaximumSupportedAssetCount() → uint256` {#PoolFactoryV24-getMaximumSupportedAssetCount--}
Get maximum supported asset count



## Return Values:
- The maximum supported asset count


# Function `isValidAsset(address asset) → bool` {#PoolFactoryV24-isValidAsset-address-}
Return boolean if the asset is supported



## Return Values:
- True if it's valid asset, false otherwise


# Function `getAssetPrice(address asset) → uint256 price` {#PoolFactoryV24-getAssetPrice-address-}
Return the latest price of a given asset


## Parameters:
- `asset`: The address of the asset


## Return Values:
- price The latest price of a given asset


# Function `getAssetType(address asset) → uint16 assetType` {#PoolFactoryV24-getAssetType-address-}
Return type of the asset


## Parameters:
- `asset`: The address of the asset


## Return Values:
- assetType The type of the asset


# Function `getAssetHandler() → address` {#PoolFactoryV24-getAssetHandler--}
Return the address of the asset handler



## Return Values:
- Address of the asset handler


# Function `setAssetHandler(address assetHandler)` {#PoolFactoryV24-setAssetHandler-address-}
Set the asset handler address


## Parameters:
- `assetHandler`: The address of the asset handler





# Function `setPoolStorageVersion(uint256 _poolStorageVersion)` {#PoolFactoryV24-setPoolStorageVersion-uint256-}
Set the pool storage version


## Parameters:
- `_poolStorageVersion`: The pool storage version







# Function `upgradePoolBatch(uint256 startIndex, uint256 endIndex, uint256 sourceVersion, uint256 targetVersion, bytes data)` {#PoolFactoryV24-upgradePoolBatch-uint256-uint256-uint256-uint256-bytes-}
Upgrade pools in batch


## Parameters:
- `startIndex`: The start index of the pool upgrade

- `endIndex`: The end index of the pool upgrade

- `sourceVersion`: The source version of the pool upgrade

- `targetVersion`: The target version of the pool upgrade

- `data`: The calldata for the target address



# Function `pause()` {#PoolFactoryV24-pause--}
call the pause the contract




# Function `unpause()` {#PoolFactoryV24-unpause--}
call the unpause the contract




# Function `isPaused() → bool` {#PoolFactoryV24-isPaused--}
Return the pause status



## Return Values:
- The pause status


# Function `getGuard(address extContract) → address guard` {#PoolFactoryV24-getGuard-address-}
Get address of the transaction guard


## Parameters:
- `extContract`: The address of the external contract


## Return Values:
- guard Return the address of the transaction guard


# Function `getAssetGuard(address extAsset) → address guard` {#PoolFactoryV24-getAssetGuard-address-}
Get address of the asset guard


## Parameters:
- `extAsset`: The address of the external asset


## Return Values:
- guard Address of the asset guard


# Function `getAddress(bytes32 name) → address destination` {#PoolFactoryV24-getAddress-bytes32-}
Get address from the Governance contract


## Parameters:
- `name`: The name of the address


## Return Values:
- destination The destination address


# Function `getDeployedFunds() → address[]` {#PoolFactoryV24-getDeployedFunds--}
Return full array of deployed funds



## Return Values:
- Full array of deployed funds


# Function `getInvestedPools(address user) → address[] investedPools` {#PoolFactoryV24-getInvestedPools-address-}
Returns all invested pools by a given user


## Parameters:
- `user`: the user address


## Return Values:
- investedPools All invested pools by a given user


# Function `getManagedPools(address manager) → address[] managedPools` {#PoolFactoryV24-getManagedPools-address-}
Returns all managed pools by a given manager


## Parameters:
- `manager`: The manager address


## Return Values:
- managedPools All managed pools by a given manager


