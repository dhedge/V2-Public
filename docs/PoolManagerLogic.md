

# Functions:
- [`initialize(address _factory, address _manager, string _managerName, address _poolLogic, struct IHasSupportedAsset.Asset[] _supportedAssets)`](#PoolManagerLogic-initialize-address-address-string-address-struct-IHasSupportedAsset-Asset---)
- [`isSupportedAsset(address asset)`](#PoolManagerLogic-isSupportedAsset-address-)
- [`isDepositAsset(address asset)`](#PoolManagerLogic-isDepositAsset-address-)
- [`validateAsset(address asset)`](#PoolManagerLogic-validateAsset-address-)
- [`changeAssets(struct IHasSupportedAsset.Asset[] _addAssets, address[] _removeAssets)`](#PoolManagerLogic-changeAssets-struct-IHasSupportedAsset-Asset---address---)
- [`getSupportedAssets()`](#PoolManagerLogic-getSupportedAssets--)
- [`getDepositAssets()`](#PoolManagerLogic-getDepositAssets--)
- [`assetBalance(address asset)`](#PoolManagerLogic-assetBalance-address-)
- [`assetValue(address asset, uint256 amount)`](#PoolManagerLogic-assetValue-address-uint256-)
- [`assetValue(address asset)`](#PoolManagerLogic-assetValue-address-)
- [`getFundComposition()`](#PoolManagerLogic-getFundComposition--)
- [`getManagerFee()`](#PoolManagerLogic-getManagerFee--)
- [`announceManagerFeeIncrease(uint256 numerator)`](#PoolManagerLogic-announceManagerFeeIncrease-uint256-)
- [`renounceManagerFeeIncrease()`](#PoolManagerLogic-renounceManagerFeeIncrease--)
- [`commitManagerFeeIncrease()`](#PoolManagerLogic-commitManagerFeeIncrease--)
- [`setManagerFeeNumerator(uint256 numerator)`](#PoolManagerLogic-setManagerFeeNumerator-uint256-)
- [`getManagerFeeIncreaseInfo()`](#PoolManagerLogic-getManagerFeeIncreaseInfo--)
- [`setPoolLogic(address _poolLogic)`](#PoolManagerLogic-setPoolLogic-address-)
- [`totalFundValue()`](#PoolManagerLogic-totalFundValue--)

# Events:
- [`AssetAdded(address fundAddress, address manager, address asset, bool isDeposit)`](#PoolManagerLogic-AssetAdded-address-address-address-bool-)
- [`AssetRemoved(address fundAddress, address manager, address asset)`](#PoolManagerLogic-AssetRemoved-address-address-address-)
- [`ManagerFeeSet(address fundAddress, address manager, uint256 numerator, uint256 denominator)`](#PoolManagerLogic-ManagerFeeSet-address-address-uint256-uint256-)
- [`ManagerFeeIncreaseAnnounced(uint256 newNumerator, uint256 announcedFeeActivationTime)`](#PoolManagerLogic-ManagerFeeIncreaseAnnounced-uint256-uint256-)
- [`ManagerFeeIncreaseRenounced()`](#PoolManagerLogic-ManagerFeeIncreaseRenounced--)
- [`PoolLogicSet(address poolLogic, address from)`](#PoolManagerLogic-PoolLogicSet-address-address-)

# Function `initialize(address _factory, address _manager, string _managerName, address _poolLogic, struct IHasSupportedAsset.Asset[] _supportedAssets)` {#PoolManagerLogic-initialize-address-address-string-address-struct-IHasSupportedAsset-Asset---}
No description
# Function `isSupportedAsset(address asset) → bool` {#PoolManagerLogic-isSupportedAsset-address-}
No description
# Function `isDepositAsset(address asset) → bool` {#PoolManagerLogic-isDepositAsset-address-}
No description
# Function `validateAsset(address asset) → bool` {#PoolManagerLogic-validateAsset-address-}
No description
# Function `changeAssets(struct IHasSupportedAsset.Asset[] _addAssets, address[] _removeAssets)` {#PoolManagerLogic-changeAssets-struct-IHasSupportedAsset-Asset---address---}
No description
# Function `getSupportedAssets() → struct IHasSupportedAsset.Asset[]` {#PoolManagerLogic-getSupportedAssets--}
No description
## Return Values:
- Return array of supported assets
# Function `getDepositAssets() → address[]` {#PoolManagerLogic-getDepositAssets--}
No description
## Return Values:
- Return array of deposit assets' addresses
# Function `assetBalance(address asset) → uint256` {#PoolManagerLogic-assetBalance-address-}
No description
# Function `assetValue(address asset, uint256 amount) → uint256` {#PoolManagerLogic-assetValue-address-uint256-}
No description
# Function `assetValue(address asset) → uint256` {#PoolManagerLogic-assetValue-address-}
No description
# Function `getFundComposition() → struct IHasSupportedAsset.Asset[] assets, uint256[] balances, uint256[] rates` {#PoolManagerLogic-getFundComposition--}
Return assets, balances of the asset and their prices

## Return Values:
- assets array of supported assets

- balances balances of each asset

- rates price of each asset in USD
# Function `getManagerFee() → uint256, uint256` {#PoolManagerLogic-getManagerFee--}
No description
# Function `announceManagerFeeIncrease(uint256 numerator)` {#PoolManagerLogic-announceManagerFeeIncrease-uint256-}
No description
# Function `renounceManagerFeeIncrease()` {#PoolManagerLogic-renounceManagerFeeIncrease--}
No description
# Function `commitManagerFeeIncrease()` {#PoolManagerLogic-commitManagerFeeIncrease--}
No description
# Function `setManagerFeeNumerator(uint256 numerator)` {#PoolManagerLogic-setManagerFeeNumerator-uint256-}
No description
# Function `getManagerFeeIncreaseInfo() → uint256, uint256` {#PoolManagerLogic-getManagerFeeIncreaseInfo--}
No description
# Function `setPoolLogic(address _poolLogic) → bool` {#PoolManagerLogic-setPoolLogic-address-}
No description
# Function `totalFundValue() → uint256` {#PoolManagerLogic-totalFundValue--}
Calculate the total fund value from the supported assets

## Return Values:
- value in USD

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
