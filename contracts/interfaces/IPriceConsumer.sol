pragma solidity ^0.6.2;
pragma experimental ABIEncoderV2;

interface IPriceConsumer {

    event AddedAsset(address asset, uint8 assetType, address aggregator);
    event RemovedAsset(address asset);

    struct Asset {
        address asset;
        uint8 assetType;
        address aggregator;
    }

    function addAsset(address asset, uint8 assetType, address aggregator) external;

    function addAssets(Asset[] memory assets) external;

    function removeAsset(address asset) external;

    function getAggregator(address asset) external view returns (address);

    function getTypeAndAggregator(address asset) external view returns (uint8, address);

    function getUSDPrice(address asset) external view returns (uint256);
}
