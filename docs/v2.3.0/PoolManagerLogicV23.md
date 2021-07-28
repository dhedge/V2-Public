

# Functions:
- [`initialize(address _factory, address _manager, string _managerName, address _poolLogic, struct IHasSupportedAssetV23.Asset[] _supportedAssets)`](#PoolManagerLogicV23-initialize-address-address-string-address-struct-IHasSupportedAssetV23-Asset---)
- [`isSupportedAsset(address asset)`](#PoolManagerLogicV23-isSupportedAsset-address-)
- [`isDepositAsset(address asset)`](#PoolManagerLogicV23-isDepositAsset-address-)
- [`validateAsset(address asset)`](#PoolManagerLogicV23-validateAsset-address-)
- [`changeAssets(struct IHasSupportedAssetV23.Asset[] _addAssets, address[] _removeAssets)`](#PoolManagerLogicV23-changeAssets-struct-IHasSupportedAssetV23-Asset---address---)
- [`getSupportedAssets()`](#PoolManagerLogicV23-getSupportedAssets--)
- [`getDepositAssets()`](#PoolManagerLogicV23-getDepositAssets--)
- [`assetBalance(address asset)`](#PoolManagerLogicV23-assetBalance-address-)
- [`assetDecimal(address asset)`](#PoolManagerLogicV23-assetDecimal-address-)
- [`assetValue(address asset, uint256 amount)`](#PoolManagerLogicV23-assetValue-address-uint256-)
- [`assetValue(address asset)`](#PoolManagerLogicV23-assetValue-address-)
- [`getFundComposition()`](#PoolManagerLogicV23-getFundComposition--)
- [`getManagerFee()`](#PoolManagerLogicV23-getManagerFee--)
- [`announceManagerFeeIncrease(uint256 numerator)`](#PoolManagerLogicV23-announceManagerFeeIncrease-uint256-)
- [`renounceManagerFeeIncrease()`](#PoolManagerLogicV23-renounceManagerFeeIncrease--)
- [`commitManagerFeeIncrease()`](#PoolManagerLogicV23-commitManagerFeeIncrease--)
- [`setManagerFeeNumerator(uint256 numerator)`](#PoolManagerLogicV23-setManagerFeeNumerator-uint256-)
- [`getManagerFeeIncreaseInfo()`](#PoolManagerLogicV23-getManagerFeeIncreaseInfo--)
- [`setPoolLogic(address _poolLogic)`](#PoolManagerLogicV23-setPoolLogic-address-)
- [`totalFundValue()`](#PoolManagerLogicV23-totalFundValue--)

# Events:
- [`AssetAdded(address fundAddress, address manager, address asset, bool isDeposit)`](#PoolManagerLogicV23-AssetAdded-address-address-address-bool-)
- [`AssetRemoved(address fundAddress, address manager, address asset)`](#PoolManagerLogicV23-AssetRemoved-address-address-address-)
- [`ManagerFeeSet(address fundAddress, address manager, uint256 numerator, uint256 denominator)`](#PoolManagerLogicV23-ManagerFeeSet-address-address-uint256-uint256-)
- [`ManagerFeeIncreaseAnnounced(uint256 newNumerator, uint256 announcedFeeActivationTime)`](#PoolManagerLogicV23-ManagerFeeIncreaseAnnounced-uint256-uint256-)
- [`ManagerFeeIncreaseRenounced()`](#PoolManagerLogicV23-ManagerFeeIncreaseRenounced--)
- [`PoolLogicSet(address poolLogic, address from)`](#PoolManagerLogicV23-PoolLogicSet-address-address-)


# Function `initialize(address _factory, address _manager, string _managerName, address _poolLogic, struct IHasSupportedAssetV23.Asset[] _supportedAssets)` {#PoolManagerLogicV23-initialize-address-address-string-address-struct-IHasSupportedAssetV23-Asset---}
No description




# Function `isSupportedAsset(address asset) → bool` {#PoolManagerLogicV23-isSupportedAsset-address-}
No description




# Function `isDepositAsset(address asset) → bool` {#PoolManagerLogicV23-isDepositAsset-address-}
No description




# Function `validateAsset(address asset) → bool` {#PoolManagerLogicV23-validateAsset-address-}
No description




# Function `changeAssets(struct IHasSupportedAssetV23.Asset[] _addAssets, address[] _removeAssets)` {#PoolManagerLogicV23-changeAssets-struct-IHasSupportedAssetV23-Asset---address---}
No description










# Function `getSupportedAssets() → struct IHasSupportedAssetV23.Asset[]` {#PoolManagerLogicV23-getSupportedAssets--}
Get all the supported assets



## Return Values:
- Return array of supported assets


# Function `getDepositAssets() → address[]` {#PoolManagerLogicV23-getDepositAssets--}
Get all the deposit assets



## Return Values:
- Return array of deposit assets' addresses


# Function `assetBalance(address asset) → uint256` {#PoolManagerLogicV23-assetBalance-address-}
Get asset balance including any staked balance in external contracts




# Function `assetDecimal(address asset) → uint256` {#PoolManagerLogicV23-assetDecimal-address-}
Get asset decimal




# Function `assetValue(address asset, uint256 amount) → uint256` {#PoolManagerLogicV23-assetValue-address-uint256-}
No description




# Function `assetValue(address asset) → uint256` {#PoolManagerLogicV23-assetValue-address-}
No description




# Function `getFundComposition() → struct IHasSupportedAssetV23.Asset[] assets, uint256[] balances, uint256[] rates` {#PoolManagerLogicV23-getFundComposition--}
Return the fund composition of the pool



## Return Values:
- assets array of supported assets

- balances balances of each asset

- rates price of each asset in USD


# Function `getManagerFee() → uint256, uint256` {#PoolManagerLogicV23-getManagerFee--}
No description






# Function `announceManagerFeeIncrease(uint256 numerator)` {#PoolManagerLogicV23-announceManagerFeeIncrease-uint256-}
No description




# Function `renounceManagerFeeIncrease()` {#PoolManagerLogicV23-renounceManagerFeeIncrease--}
No description




# Function `commitManagerFeeIncrease()` {#PoolManagerLogicV23-commitManagerFeeIncrease--}
No description




# Function `setManagerFeeNumerator(uint256 numerator)` {#PoolManagerLogicV23-setManagerFeeNumerator-uint256-}
No description




# Function `getManagerFeeIncreaseInfo() → uint256, uint256` {#PoolManagerLogicV23-getManagerFeeIncreaseInfo--}
No description




# Function `setPoolLogic(address _poolLogic) → bool` {#PoolManagerLogicV23-setPoolLogic-address-}
No description




# Function `totalFundValue() → uint256` {#PoolManagerLogicV23-totalFundValue--}
Return the total fund value of the pool



## Return Values:
- value in USD


