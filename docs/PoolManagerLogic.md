Logic implmentation for pool manager

# Functions:
- [`initialize(address _factory, address _manager, string _managerName, address _poolLogic, uint256 _managerFeeNumerator, struct IHasSupportedAsset.Asset[] _supportedAssets)`](#PoolManagerLogic-initialize-address-address-string-address-uint256-struct-IHasSupportedAsset-Asset---)
- [`isSupportedAsset(address asset)`](#PoolManagerLogic-isSupportedAsset-address-)
- [`isDepositAsset(address asset)`](#PoolManagerLogic-isDepositAsset-address-)
- [`validateAsset(address asset)`](#PoolManagerLogic-validateAsset-address-)
- [`changeAssets(struct IHasSupportedAsset.Asset[] _addAssets, address[] _removeAssets)`](#PoolManagerLogic-changeAssets-struct-IHasSupportedAsset-Asset---address---)
- [`getSupportedAssets()`](#PoolManagerLogic-getSupportedAssets--)
- [`getDepositAssets()`](#PoolManagerLogic-getDepositAssets--)
- [`assetBalance(address asset)`](#PoolManagerLogic-assetBalance-address-)
- [`assetDecimal(address asset)`](#PoolManagerLogic-assetDecimal-address-)
- [`assetValue(address asset, uint256 amount)`](#PoolManagerLogic-assetValue-address-uint256-)
- [`assetValue(address asset)`](#PoolManagerLogic-assetValue-address-)
- [`getFundComposition()`](#PoolManagerLogic-getFundComposition--)
- [`totalFundValue()`](#PoolManagerLogic-totalFundValue--)
- [`getManagerFee()`](#PoolManagerLogic-getManagerFee--)
- [`getMaximumManagerFee()`](#PoolManagerLogic-getMaximumManagerFee--)
- [`getMaximumManagerFeeChange()`](#PoolManagerLogic-getMaximumManagerFeeChange--)
- [`setManagerFeeNumerator(uint256 numerator)`](#PoolManagerLogic-setManagerFeeNumerator-uint256-)
- [`announceManagerFeeIncrease(uint256 numerator)`](#PoolManagerLogic-announceManagerFeeIncrease-uint256-)
- [`renounceManagerFeeIncrease()`](#PoolManagerLogic-renounceManagerFeeIncrease--)
- [`commitManagerFeeIncrease()`](#PoolManagerLogic-commitManagerFeeIncrease--)
- [`getManagerFeeIncreaseInfo()`](#PoolManagerLogic-getManagerFeeIncreaseInfo--)
- [`setPoolLogic(address _poolLogic)`](#PoolManagerLogic-setPoolLogic-address-)

# Events:
- [`AssetAdded(address fundAddress, address manager, address asset, bool isDeposit)`](#PoolManagerLogic-AssetAdded-address-address-address-bool-)
- [`AssetRemoved(address fundAddress, address manager, address asset)`](#PoolManagerLogic-AssetRemoved-address-address-address-)
- [`ManagerFeeSet(address fundAddress, address manager, uint256 numerator, uint256 denominator)`](#PoolManagerLogic-ManagerFeeSet-address-address-uint256-uint256-)
- [`ManagerFeeIncreaseAnnounced(uint256 newNumerator, uint256 announcedFeeActivationTime)`](#PoolManagerLogic-ManagerFeeIncreaseAnnounced-uint256-uint256-)
- [`ManagerFeeIncreaseRenounced()`](#PoolManagerLogic-ManagerFeeIncreaseRenounced--)
- [`PoolLogicSet(address poolLogic, address from)`](#PoolManagerLogic-PoolLogicSet-address-address-)


# Function `initialize(address _factory, address _manager, string _managerName, address _poolLogic, uint256 _managerFeeNumerator, struct IHasSupportedAsset.Asset[] _supportedAssets)` {#PoolManagerLogic-initialize-address-address-string-address-uint256-struct-IHasSupportedAsset-Asset---}
initialize the pool manager


## Parameters:
- `_factory`: address of the factory

- `_manager`: address of the manager

- `_managerName`: name of the manager

- `_poolLogic`: address of the pool logic

- `_managerFeeNumerator`: numerator of the manager fee

- `_supportedAssets`: array of supported assets



# Function `isSupportedAsset(address asset) → bool` {#PoolManagerLogic-isSupportedAsset-address-}
Return true if it's supported asset, false otherwise


## Parameters:
- `asset`: address of the asset



# Function `isDepositAsset(address asset) → bool` {#PoolManagerLogic-isDepositAsset-address-}
Return true if it's deposit asset, false otherwise


## Parameters:
- `asset`: address of the asset



# Function `validateAsset(address asset) → bool` {#PoolManagerLogic-validateAsset-address-}
Return true if it's valid asset, false otherwise


## Parameters:
- `asset`: address of the asset



# Function `changeAssets(struct IHasSupportedAsset.Asset[] _addAssets, address[] _removeAssets)` {#PoolManagerLogic-changeAssets-struct-IHasSupportedAsset-Asset---address---}
Change assets of the pool


## Parameters:
- `_addAssets`: array of assets to add

- `_removeAssets`: array of asset addresses to remove









# Function `getSupportedAssets() → struct IHasSupportedAsset.Asset[]` {#PoolManagerLogic-getSupportedAssets--}
Get all the supported assets



## Return Values:
- Return array of supported assets


# Function `getDepositAssets() → address[]` {#PoolManagerLogic-getDepositAssets--}
Get all the deposit assets



## Return Values:
- Return array of deposit assets' addresses


# Function `assetBalance(address asset) → uint256 balance` {#PoolManagerLogic-assetBalance-address-}
Get asset balance including any staked balance in external contracts



## Return Values:
- balance of the asset


# Function `assetDecimal(address asset) → uint256 decimal` {#PoolManagerLogic-assetDecimal-address-}
Get asset decimal



## Return Values:
- decimal of the asset


# Function `assetValue(address asset, uint256 amount) → uint256 value` {#PoolManagerLogic-assetValue-address-uint256-}
Get value of the asset


## Parameters:
- `asset`: address of the asset

- `amount`: amount of the asset


## Return Values:
- value of the asset


# Function `assetValue(address asset) → uint256 value` {#PoolManagerLogic-assetValue-address-}
Get value of the asset


## Parameters:
- `asset`: address of the asset


## Return Values:
- value of the asset


# Function `getFundComposition() → struct IHasSupportedAsset.Asset[] assets, uint256[] balances, uint256[] rates` {#PoolManagerLogic-getFundComposition--}
Return the fund composition of the pool



## Return Values:
- assets array of supported assets

- balances balances of each asset

- rates price of each asset in USD


# Function `totalFundValue() → uint256` {#PoolManagerLogic-totalFundValue--}
Return the total fund value of the pool



## Return Values:
- value in USD


# Function `getManagerFee() → uint256, uint256` {#PoolManagerLogic-getManagerFee--}
Return the manager fees




# Function `getMaximumManagerFee() → uint256 numerator, uint256 denominator` {#PoolManagerLogic-getMaximumManagerFee--}
Get maximum manager fee



## Return Values:
- numerator numberator of the maximum manager fee

- denominator denominator of the maximum manager fee


# Function `getMaximumManagerFeeChange() → uint256 change` {#PoolManagerLogic-getMaximumManagerFeeChange--}
Get maximum manager fee change



## Return Values:
- change change of the maximum manager fee


# Function `setManagerFeeNumerator(uint256 numerator)` {#PoolManagerLogic-setManagerFeeNumerator-uint256-}
Manager can decrease performance fee


## Parameters:
- `numerator`: numberator of the performance fee to set





# Function `announceManagerFeeIncrease(uint256 numerator)` {#PoolManagerLogic-announceManagerFeeIncrease-uint256-}
Manager can announce an increase to the performance fee





# Function `renounceManagerFeeIncrease()` {#PoolManagerLogic-renounceManagerFeeIncrease--}
Manager can cancel the performance fee increase





# Function `commitManagerFeeIncrease()` {#PoolManagerLogic-commitManagerFeeIncrease--}
Manager can commit the performance fee increase





# Function `getManagerFeeIncreaseInfo() → uint256, uint256` {#PoolManagerLogic-getManagerFeeIncreaseInfo--}
Get manager fee increase information




# Function `setPoolLogic(address _poolLogic) → bool` {#PoolManagerLogic-setPoolLogic-address-}
Setter for poolLogic contract





# Event `AssetAdded(address fundAddress, address manager, address asset, bool isDeposit)` {#PoolManagerLogic-AssetAdded-address-address-address-bool-}
No description

# Event `AssetRemoved(address fundAddress, address manager, address asset)` {#PoolManagerLogic-AssetRemoved-address-address-address-}
No description

# Event `ManagerFeeSet(address fundAddress, address manager, uint256 numerator, uint256 denominator)` {#PoolManagerLogic-ManagerFeeSet-address-address-uint256-uint256-}
No description

# Event `ManagerFeeIncreaseAnnounced(uint256 newNumerator, uint256 announcedFeeActivationTime)` {#PoolManagerLogic-ManagerFeeIncreaseAnnounced-uint256-uint256-}
No description

# Event `ManagerFeeIncreaseRenounced()` {#PoolManagerLogic-ManagerFeeIncreaseRenounced--}
No description

# Event `PoolLogicSet(address poolLogic, address from)` {#PoolManagerLogic-PoolLogicSet-address-address-}
No description

