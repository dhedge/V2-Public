Returns Chainlink USD price feed with 18 decimals
Asset types:
0 = Chainlink direct USD price feed with 8 decimals

# Functions:
- [`initialize(address _poolFactory, struct IAssetHandler.Asset[] assets)`](#AssetHandler-initialize-address-struct-IAssetHandler-Asset---)
- [`getAssetTypeAndAggregator(address asset)`](#AssetHandler-getAssetTypeAndAggregator-address-)
- [`getUSDPrice(address asset)`](#AssetHandler-getUSDPrice-address-)
- [`setPoolFactory(address _poolFactory)`](#AssetHandler-setPoolFactory-address-)
- [`setChainlinkTimeout(uint256 newTimeoutPeriod)`](#AssetHandler-setChainlinkTimeout-uint256-)
- [`addAsset(address asset, uint8 assetType, address aggregator)`](#AssetHandler-addAsset-address-uint8-address-)
- [`addAssets(struct IAssetHandler.Asset[] assets)`](#AssetHandler-addAssets-struct-IAssetHandler-Asset---)
- [`removeAsset(address asset)`](#AssetHandler-removeAsset-address-)


# Function `initialize(address _poolFactory, struct IAssetHandler.Asset[] assets)` {#AssetHandler-initialize-address-struct-IAssetHandler-Asset---}
No description
# Function `getAssetTypeAndAggregator(address asset) → uint8, address` {#AssetHandler-getAssetTypeAndAggregator-address-}
No description
# Function `getUSDPrice(address asset) → uint256 price` {#AssetHandler-getUSDPrice-address-}
Calculate the USD price of a given asset.

## Parameters:
- `asset`: the asset address

## Return Values:
- price Returns the latest price of a given asset (decimal: 18)
# Function `setPoolFactory(address _poolFactory)` {#AssetHandler-setPoolFactory-address-}
No description
# Function `setChainlinkTimeout(uint256 newTimeoutPeriod)` {#AssetHandler-setChainlinkTimeout-uint256-}
No description
# Function `addAsset(address asset, uint8 assetType, address aggregator)` {#AssetHandler-addAsset-address-uint8-address-}
No description
# Function `addAssets(struct IAssetHandler.Asset[] assets)` {#AssetHandler-addAssets-struct-IAssetHandler-Asset---}
No description
# Function `removeAsset(address asset)` {#AssetHandler-removeAsset-address-}
No description

