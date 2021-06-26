## `AssetHandler`



Returns Chainlink USD price feed with 18 decimals
Asset types:
0 = Chainlink direct USD price feed with 8 decimals


### `initialize(address _poolFactory, struct IAssetHandler.Asset[] assets)` (public)





### `getAssetTypeAndAggregator(address asset) → uint8, address` (public)





### `getUSDPrice(address asset) → uint256 price` (public)

Currenly only use chainlink price feed.


Calculate the USD price of a given asset.


### `setPoolFactory(address _poolFactory)` (external)





### `setChainlinkTimeout(uint256 newTimeoutPeriod)` (external)





### `addAsset(address asset, uint8 assetType, address aggregator)` (public)

Add valid asset with price aggregator



### `addAssets(struct IAssetHandler.Asset[] assets)` (public)





### `removeAsset(address asset)` (public)

Remove valid asset




