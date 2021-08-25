

# Functions:
- [`initialize(struct IAssetHandler.Asset[] assets)`](#AssetHandler-initialize-struct-IAssetHandler-Asset---)
- [`getUSDPrice(address asset)`](#AssetHandler-getUSDPrice-address-)
- [`setChainlinkTimeout(uint256 newTimeoutPeriod)`](#AssetHandler-setChainlinkTimeout-uint256-)
- [`addAsset(address asset, uint16 assetType, address aggregator)`](#AssetHandler-addAsset-address-uint16-address-)
- [`addAssets(struct IAssetHandler.Asset[] assets)`](#AssetHandler-addAssets-struct-IAssetHandler-Asset---)
- [`removeAsset(address asset)`](#AssetHandler-removeAsset-address-)

# Events:
- [`SetChainlinkTimeout(uint256 _chainlinkTimeout)`](#AssetHandler-SetChainlinkTimeout-uint256-)


# Function `initialize(struct IAssetHandler.Asset[] assets)` {#AssetHandler-initialize-struct-IAssetHandler-Asset---}
initialisation for the contract


## Parameters:
- `assets`: An array of assets to initialise



# Function `getUSDPrice(address asset) → uint256 price` {#AssetHandler-getUSDPrice-address-}
Currenly only use chainlink price feed.


## Parameters:
- `asset`: the asset address


## Return Values:
- price Returns the latest price of a given asset (decimal: 18)


# Function `setChainlinkTimeout(uint256 newTimeoutPeriod)` {#AssetHandler-setChainlinkTimeout-uint256-}
Setting the timeout for the Chainlink price feed


## Parameters:
- `newTimeoutPeriod`: A new time in seconds for the timeout



# Function `addAsset(address asset, uint16 assetType, address aggregator)` {#AssetHandler-addAsset-address-uint16-address-}
Add valid asset with price aggregator


## Parameters:
- `asset`: Address of the asset to add

- `assetType`: Type of the asset

- `aggregator`: Address of the aggregator



# Function `addAssets(struct IAssetHandler.Asset[] assets)` {#AssetHandler-addAssets-struct-IAssetHandler-Asset---}
Add valid assets with price aggregator


## Parameters:
- `assets`: An array of assets to add



# Function `removeAsset(address asset)` {#AssetHandler-removeAsset-address-}
Remove valid asset


## Parameters:
- `asset`: Address of the asset to remove



