

# Functions:
- [`initialize(address _poolLogic, address _managerLogic, address assetHandler, address _daoAddress, address _governanceAddress)`](#PoolFactory-initialize-address-address-address-address-address-)
- [`createFund(bool _privatePool, address _manager, string _managerName, string _fundName, string _fundSymbol, uint256 _managerFeeNumerator, struct IHasSupportedAsset.Asset[] _supportedAssets)`](#PoolFactory-createFund-bool-address-string-string-string-uint256-struct-IHasSupportedAsset-Asset---)
- [`setDAOAddress(address _daoAddress)`](#PoolFactory-setDAOAddress-address-)
- [`setGovernanceAddress(address _governanceAddress)`](#PoolFactory-setGovernanceAddress-address-)
- [`setDaoFee(uint256 numerator, uint256 denominator)`](#PoolFactory-setDaoFee-uint256-uint256-)
- [`getDaoFee()`](#PoolFactory-getDaoFee--)
- [`getMaximumManagerFee()`](#PoolFactory-getMaximumManagerFee--)
- [`setMaximumManagerFee(uint256 numerator)`](#PoolFactory-setMaximumManagerFee-uint256-)
- [`setMaximumManagerFeeNumeratorChange(uint256 amount)`](#PoolFactory-setMaximumManagerFeeNumeratorChange-uint256-)
- [`setManagerFeeNumeratorChangeDelay(uint256 delay)`](#PoolFactory-setManagerFeeNumeratorChangeDelay-uint256-)
- [`setExitCooldown(uint256 cooldown)`](#PoolFactory-setExitCooldown-uint256-)
- [`getExitCooldown()`](#PoolFactory-getExitCooldown--)
- [`setMaximumSupportedAssetCount(uint256 count)`](#PoolFactory-setMaximumSupportedAssetCount-uint256-)
- [`getMaximumSupportedAssetCount()`](#PoolFactory-getMaximumSupportedAssetCount--)
- [`isValidAsset(address asset)`](#PoolFactory-isValidAsset-address-)
- [`getAssetPrice(address asset)`](#PoolFactory-getAssetPrice-address-)
- [`getAssetType(address asset)`](#PoolFactory-getAssetType-address-)
- [`getAssetHandler()`](#PoolFactory-getAssetHandler--)
- [`setAssetHandler(address assetHandler)`](#PoolFactory-setAssetHandler-address-)
- [`setPoolStorageVersion(uint256 _poolStorageVersion)`](#PoolFactory-setPoolStorageVersion-uint256-)
- [`upgradePoolBatch(uint256 startIndex, uint256 endIndex, uint256 sourceVersion, uint256 targetVersion, bytes data)`](#PoolFactory-upgradePoolBatch-uint256-uint256-uint256-uint256-bytes-)
- [`pause()`](#PoolFactory-pause--)
- [`unpause()`](#PoolFactory-unpause--)
- [`isPaused()`](#PoolFactory-isPaused--)
- [`getGuard(address extContract)`](#PoolFactory-getGuard-address-)
- [`getAssetGuard(address extAsset)`](#PoolFactory-getAssetGuard-address-)
- [`getAddress(bytes32 name)`](#PoolFactory-getAddress-bytes32-)
- [`getDeployedFunds()`](#PoolFactory-getDeployedFunds--)
- [`getInvestedPools(address user)`](#PoolFactory-getInvestedPools-address-)
- [`getManagedPools(address manager)`](#PoolFactory-getManagedPools-address-)

# Events:
- [`FundCreated(address fundAddress, bool isPoolPrivate, string fundName, string managerName, address manager, uint256 time, uint256 managerFeeNumerator, uint256 managerFeeDenominator)`](#PoolFactory-FundCreated-address-bool-string-string-address-uint256-uint256-uint256-)
- [`DAOAddressSet(address daoAddress)`](#PoolFactory-DAOAddressSet-address-)
- [`GovernanceAddressSet(address governanceAddress)`](#PoolFactory-GovernanceAddressSet-address-)
- [`DaoFeeSet(uint256 numerator, uint256 denominator)`](#PoolFactory-DaoFeeSet-uint256-uint256-)
- [`ExitFeeSet(uint256 numerator, uint256 denominator)`](#PoolFactory-ExitFeeSet-uint256-uint256-)
- [`ExitCooldownSet(uint256 cooldown)`](#PoolFactory-ExitCooldownSet-uint256-)
- [`MaximumSupportedAssetCountSet(uint256 count)`](#PoolFactory-MaximumSupportedAssetCountSet-uint256-)
- [`LogUpgrade(address manager, address pool)`](#PoolFactory-LogUpgrade-address-address-)
- [`SetPoolManagerFee(uint256 numerator, uint256 denominator)`](#PoolFactory-SetPoolManagerFee-uint256-uint256-)
- [`SetMaximumManagerFee(uint256 numerator, uint256 denominator)`](#PoolFactory-SetMaximumManagerFee-uint256-uint256-)
- [`SetMaximumManagerFeeNumeratorChange(uint256 amount)`](#PoolFactory-SetMaximumManagerFeeNumeratorChange-uint256-)
- [`SetAssetHandler(address assetHandler)`](#PoolFactory-SetAssetHandler-address-)
- [`SetPoolStorageVersion(uint256 poolStorageVersion)`](#PoolFactory-SetPoolStorageVersion-uint256-)
- [`SetManagerFeeNumeratorChangeDelay(uint256 delay)`](#PoolFactory-SetManagerFeeNumeratorChangeDelay-uint256-)


# Function `initialize(address _poolLogic, address _managerLogic, address assetHandler, address _daoAddress, address _governanceAddress)` {#PoolFactory-initialize-address-address-address-address-address-}
Initialize the factory


## Parameters:
- `_poolLogic`: The pool logic address

- `_managerLogic`: The manager logic address

- `assetHandler`: The address of the asset handler

- `_daoAddress`: The address of the DAO

- `_governanceAddress`: The address of the governance contract



# Function `createFund(bool _privatePool, address _manager, string _managerName, string _fundName, string _fundSymbol, uint256 _managerFeeNumerator, struct IHasSupportedAsset.Asset[] _supportedAssets) → address fund` {#PoolFactory-createFund-bool-address-string-string-string-uint256-struct-IHasSupportedAsset-Asset---}
Function to create a new fund


## Parameters:
- `_privatePool`: A boolean indicating whether the fund is private or not

- `_manager`: A manager address

- `_managerName`: The name of the manager

- `_fundName`: The name of the fund

- `_fundSymbol`: The symbol of the fund

- `_managerFeeNumerator`: The numerator of the manager fee

- `_supportedAssets`: An array of supported assets


## Return Values:
- fund Address of the fund


# Function `setDAOAddress(address _daoAddress)` {#PoolFactory-setDAOAddress-address-}
Set the DAO address


## Parameters:
- `_daoAddress`: The address of the DAO





# Function `setGovernanceAddress(address _governanceAddress)` {#PoolFactory-setGovernanceAddress-address-}
Set the governance address


## Parameters:
- `_governanceAddress`: The address of the governance contract





# Function `setDaoFee(uint256 numerator, uint256 denominator)` {#PoolFactory-setDaoFee-uint256-uint256-}
Set the DAO fee


## Parameters:
- `numerator`: The numerator of the DAO fee

- `denominator`: The denominator of the DAO fee





# Function `getDaoFee() → uint256, uint256` {#PoolFactory-getDaoFee--}
Get the DAO fee



## Return Values:
- The numerator of the DAO fee

- The denominator of the DAO fee


# Function `getMaximumManagerFee() → uint256, uint256` {#PoolFactory-getMaximumManagerFee--}
Get the maximum manager fee



## Return Values:
- The maximum manager fee numerator

- The maximum manager fee denominator


# Function `setMaximumManagerFee(uint256 numerator)` {#PoolFactory-setMaximumManagerFee-uint256-}
Set the maximum manager fee


## Parameters:
- `numerator`: The numerator of the maximum manager fee





# Function `setMaximumManagerFeeNumeratorChange(uint256 amount)` {#PoolFactory-setMaximumManagerFeeNumeratorChange-uint256-}
Set maximum manager fee numberator change


## Parameters:
- `amount`: The amount for the maximum manager fee numerator change



# Function `setManagerFeeNumeratorChangeDelay(uint256 delay)` {#PoolFactory-setManagerFeeNumeratorChangeDelay-uint256-}
Set manager fee numberator change delay


## Parameters:
- `delay`: The delay in seconds for the manager fee numerator change



# Function `setExitCooldown(uint256 cooldown)` {#PoolFactory-setExitCooldown-uint256-}
Set exit cool down time (in seconds)


## Parameters:
- `cooldown`: The cool down time in seconds





# Function `getExitCooldown() → uint256` {#PoolFactory-getExitCooldown--}
Get the exit cool down time (in seconds)



## Return Values:
- The exit cool down time in seconds


# Function `setMaximumSupportedAssetCount(uint256 count)` {#PoolFactory-setMaximumSupportedAssetCount-uint256-}
Set maximum supported asset count


## Parameters:
- `count`: The maximum supported asset count





# Function `getMaximumSupportedAssetCount() → uint256` {#PoolFactory-getMaximumSupportedAssetCount--}
Get maximum supported asset count



## Return Values:
- The maximum supported asset count


# Function `isValidAsset(address asset) → bool` {#PoolFactory-isValidAsset-address-}
Return boolean if the asset is supported



## Return Values:
- True if it's valid asset, false otherwise


# Function `getAssetPrice(address asset) → uint256 price` {#PoolFactory-getAssetPrice-address-}
Return the latest price of a given asset


## Parameters:
- `asset`: The address of the asset


## Return Values:
- price The latest price of a given asset


# Function `getAssetType(address asset) → uint16 assetType` {#PoolFactory-getAssetType-address-}
Return type of the asset


## Parameters:
- `asset`: The address of the asset


## Return Values:
- assetType The type of the asset


# Function `getAssetHandler() → address` {#PoolFactory-getAssetHandler--}
Return the address of the asset handler



## Return Values:
- Address of the asset handler


# Function `setAssetHandler(address assetHandler)` {#PoolFactory-setAssetHandler-address-}
Set the asset handler address


## Parameters:
- `assetHandler`: The address of the asset handler





# Function `setPoolStorageVersion(uint256 _poolStorageVersion)` {#PoolFactory-setPoolStorageVersion-uint256-}
Set the pool storage version


## Parameters:
- `_poolStorageVersion`: The pool storage version







# Function `upgradePoolBatch(uint256 startIndex, uint256 endIndex, uint256 sourceVersion, uint256 targetVersion, bytes data)` {#PoolFactory-upgradePoolBatch-uint256-uint256-uint256-uint256-bytes-}
Upgrade pools in batch


## Parameters:
- `startIndex`: The start index of the pool upgrade

- `endIndex`: The end index of the pool upgrade

- `sourceVersion`: The source version of the pool upgrade

- `targetVersion`: The target version of the pool upgrade

- `data`: The calldata for the target address



# Function `pause()` {#PoolFactory-pause--}
call the pause the contract




# Function `unpause()` {#PoolFactory-unpause--}
call the unpause the contract




# Function `isPaused() → bool` {#PoolFactory-isPaused--}
Return the pause status



## Return Values:
- The pause status


# Function `getGuard(address extContract) → address guard` {#PoolFactory-getGuard-address-}
Get address of the transaction guard


## Parameters:
- `extContract`: The address of the external contract


## Return Values:
- guard Return the address of the transaction guard


# Function `getAssetGuard(address extAsset) → address guard` {#PoolFactory-getAssetGuard-address-}
Get address of the asset guard


## Parameters:
- `extAsset`: The address of the external asset


## Return Values:
- guard Address of the asset guard


# Function `getAddress(bytes32 name) → address destination` {#PoolFactory-getAddress-bytes32-}
Get address from the Governance contract


## Parameters:
- `name`: The name of the address


## Return Values:
- destination The destination address


# Function `getDeployedFunds() → address[]` {#PoolFactory-getDeployedFunds--}
Return full array of deployed funds



## Return Values:
- Full array of deployed funds


# Function `getInvestedPools(address user) → address[] investedPools` {#PoolFactory-getInvestedPools-address-}
Returns all invested pools by a given user


## Parameters:
- `user`: the user address


## Return Values:
- investedPools All invested pools by a given user


# Function `getManagedPools(address manager) → address[] managedPools` {#PoolFactory-getManagedPools-address-}
Returns all managed pools by a given manager


## Parameters:
- `manager`: The manager address


## Return Values:
- managedPools All managed pools by a given manager


