

# Functions:
- [`initialize(address _factory, address _manager, string _managerName, address _poolLogic, uint256 _performanceFeeNumerator, struct IHasSupportedAssetV24.Asset[] _supportedAssets)`](#PoolManagerLogicV24-initialize-address-address-string-address-uint256-struct-IHasSupportedAssetV24-Asset---)
- [`isSupportedAsset(address asset)`](#PoolManagerLogicV24-isSupportedAsset-address-)
- [`isDepositAsset(address asset)`](#PoolManagerLogicV24-isDepositAsset-address-)
- [`validateAsset(address asset)`](#PoolManagerLogicV24-validateAsset-address-)
- [`changeAssets(struct IHasSupportedAssetV24.Asset[] _addAssets, address[] _removeAssets)`](#PoolManagerLogicV24-changeAssets-struct-IHasSupportedAssetV24-Asset---address---)
- [`getSupportedAssets()`](#PoolManagerLogicV24-getSupportedAssets--)
- [`getDepositAssets()`](#PoolManagerLogicV24-getDepositAssets--)
- [`assetBalance(address asset)`](#PoolManagerLogicV24-assetBalance-address-)
- [`assetDecimal(address asset)`](#PoolManagerLogicV24-assetDecimal-address-)
- [`assetValue(address asset, uint256 amount)`](#PoolManagerLogicV24-assetValue-address-uint256-)
- [`assetValue(address asset)`](#PoolManagerLogicV24-assetValue-address-)
- [`getFundComposition()`](#PoolManagerLogicV24-getFundComposition--)
- [`totalFundValue()`](#PoolManagerLogicV24-totalFundValue--)
- [`getManagerFee()`](#PoolManagerLogicV24-getManagerFee--)
- [`getMaximumManagerFee()`](#PoolManagerLogicV24-getMaximumManagerFee--)
- [`getMaximumManagerFeeChange()`](#PoolManagerLogicV24-getMaximumManagerFeeChange--)
- [`setPerformanceFeeNumerator(uint256 numerator)`](#PoolManagerLogicV24-setPerformanceFeeNumerator-uint256-)
- [`announceManagerFeeIncrease(uint256 numerator)`](#PoolManagerLogicV24-announceManagerFeeIncrease-uint256-)
- [`renounceManagerFeeIncrease()`](#PoolManagerLogicV24-renounceManagerFeeIncrease--)
- [`commitManagerFeeIncrease()`](#PoolManagerLogicV24-commitManagerFeeIncrease--)
- [`getManagerFeeIncreaseInfo()`](#PoolManagerLogicV24-getManagerFeeIncreaseInfo--)
- [`setPoolLogic(address _poolLogic)`](#PoolManagerLogicV24-setPoolLogic-address-)

# Events:
- [`AssetAdded(address fundAddress, address manager, address asset, bool isDeposit)`](#PoolManagerLogicV24-AssetAdded-address-address-address-bool-)
- [`AssetRemoved(address fundAddress, address manager, address asset)`](#PoolManagerLogicV24-AssetRemoved-address-address-address-)
- [`ManagerFeeSet(address fundAddress, address manager, uint256 numerator, uint256 denominator)`](#PoolManagerLogicV24-ManagerFeeSet-address-address-uint256-uint256-)
- [`ManagerFeeIncreaseAnnounced(uint256 newNumerator, uint256 announcedFeeActivationTime)`](#PoolManagerLogicV24-ManagerFeeIncreaseAnnounced-uint256-uint256-)
- [`ManagerFeeIncreaseRenounced()`](#PoolManagerLogicV24-ManagerFeeIncreaseRenounced--)
- [`PoolLogicSet(address poolLogic, address from)`](#PoolManagerLogicV24-PoolLogicSet-address-address-)


# Function `initialize(address _factory, address _manager, string _managerName, address _poolLogic, uint256 _performanceFeeNumerator, struct IHasSupportedAssetV24.Asset[] _supportedAssets)` {#PoolManagerLogicV24-initialize-address-address-string-address-uint256-struct-IHasSupportedAssetV24-Asset---}
No description




# Function `isSupportedAsset(address asset) → bool` {#PoolManagerLogicV24-isSupportedAsset-address-}
No description




# Function `isDepositAsset(address asset) → bool` {#PoolManagerLogicV24-isDepositAsset-address-}
No description




# Function `validateAsset(address asset) → bool` {#PoolManagerLogicV24-validateAsset-address-}
No description




# Function `changeAssets(struct IHasSupportedAssetV24.Asset[] _addAssets, address[] _removeAssets)` {#PoolManagerLogicV24-changeAssets-struct-IHasSupportedAssetV24-Asset---address---}
No description










# Function `getSupportedAssets() → struct IHasSupportedAssetV24.Asset[]` {#PoolManagerLogicV24-getSupportedAssets--}
Get all the supported assets



## Return Values:
- Return array of supported assets


# Function `getDepositAssets() → address[]` {#PoolManagerLogicV24-getDepositAssets--}
Get all the deposit assets



## Return Values:
- Return array of deposit assets' addresses


# Function `assetBalance(address asset) → uint256` {#PoolManagerLogicV24-assetBalance-address-}
Get asset balance including any staked balance in external contracts




# Function `assetDecimal(address asset) → uint256` {#PoolManagerLogicV24-assetDecimal-address-}
Get asset decimal




# Function `assetValue(address asset, uint256 amount) → uint256` {#PoolManagerLogicV24-assetValue-address-uint256-}
No description




# Function `assetValue(address asset) → uint256` {#PoolManagerLogicV24-assetValue-address-}
No description




# Function `getFundComposition() → struct IHasSupportedAssetV24.Asset[] assets, uint256[] balances, uint256[] rates` {#PoolManagerLogicV24-getFundComposition--}
Return the fund composition of the pool



## Return Values:
- assets array of supported assets

- balances balances of each asset

- rates price of each asset in USD


# Function `totalFundValue() → uint256` {#PoolManagerLogicV24-totalFundValue--}
Return the total fund value of the pool



## Return Values:
- value in USD


# Function `getManagerFee() → uint256, uint256` {#PoolManagerLogicV24-getManagerFee--}
No description




# Function `getMaximumManagerFee() → uint256, uint256` {#PoolManagerLogicV24-getMaximumManagerFee--}
No description




# Function `getMaximumManagerFeeChange() → uint256` {#PoolManagerLogicV24-getMaximumManagerFeeChange--}
No description




# Function `setPerformanceFeeNumerator(uint256 numerator)` {#PoolManagerLogicV24-setPerformanceFeeNumerator-uint256-}
Manager can decrease performance fee






# Function `announceManagerFeeIncrease(uint256 numerator)` {#PoolManagerLogicV24-announceManagerFeeIncrease-uint256-}
Manager can announce an increase to the performance fee





# Function `renounceManagerFeeIncrease()` {#PoolManagerLogicV24-renounceManagerFeeIncrease--}
Manager can cancel the performance fee increase





# Function `commitManagerFeeIncrease()` {#PoolManagerLogicV24-commitManagerFeeIncrease--}
Manager can commit the performance fee increase





# Function `getManagerFeeIncreaseInfo() → uint256, uint256` {#PoolManagerLogicV24-getManagerFeeIncreaseInfo--}
No description




# Function `setPoolLogic(address _poolLogic) → bool` {#PoolManagerLogicV24-setPoolLogic-address-}
Setter for poolLogic contract





